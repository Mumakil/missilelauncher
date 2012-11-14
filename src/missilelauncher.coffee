HID = require 'node-hid'
Q = require 'q'

LAUNCHER_COMMANDS =
  DOWN    : 0x01
  UP      : 0x02
  LEFT    : 0x04
  RIGHT   : 0x08
  FIRE    : 0x10
  STOP    : 0x20

VENDOR_ID = 0x2123
PRODUCT_ID = 0x1010

extend = (dest, source...) ->
  for src in source when typeof src == 'object'
    dest[key] = src[key] for key in Object.keys src
  dest

# Default config for a DC Thunder missile launcher
defaultConfig = 
  # Milliseconds it takes to turn the turret from side to side
  FULL_TURN_TIME: 5465 # 5500
  # Milliseconds it takes to turn the turret from bottom to top
  FULL_PITCH_TIME: 835 # 1100
  # Millisencods it takes to fire
  FIRING_TIME: 3500

  # Full angle in degrees that the turret turns horizontally
  FULL_HORIZONTAL_ANGLE: 330
  # Full angle in dedgrees that the turret turns vertically
  FULL_VERTICAL_ANGLE: 35
  
  # Angle limits
  MAX_HORIZONTAL_ANGLE: 138 # 165
  MIN_HORIZONTAL_ANGLE: -138 # -165
  MAX_VERTICAL_ANGLE: 28 # 30
  MIN_VERTICAL_ANGLE: -6 # 5
  
  log: true

class MissileLauncher

  @findLaunchers: ->
    devices = HID.devices()
    match = (device) ->
      device.vendorId == VENDOR_ID && device.productId == PRODUCT_ID
    launchers = (device.path for device in devices when match(device))

  @defaultConfig: defaultConfig

  constructor: (options) ->
    @config = extend {}, MissileLauncher.defaultConfig, options.config
    @config.FULL_VERTICAL_ANGLE = @config.MAX_VERTICAL_ANGLE - @config.MIN_VERTICAL_ANGLE
    @config.FULL_HORIZONTAL_ANGLE = @config.MAX_HORIZONTAL_ANGLE - @config.MIN_HORIZONTAL_ANGLE
    @config.HORIZONTAL_TURN_RATE = @config.FULL_TURN_TIME / @config.FULL_HORIZONTAL_ANGLE
    @config.VERTICAL_TURN_RATE = @config.FULL_PITCH_TIME / @config.FULL_VERTICAL_ANGLE
    if options.device
      @device = options.device
    else
      @device = new HID.HID(options.path)
    @busy = false
    @verticalAngle = undefined
    @horizontalAngle = undefined

  sendCommand: (command) ->
    return false unless typeof command == 'string'
    cmd = LAUNCHER_COMMANDS[command.toUpperCase()]
    @device.write [0x02, cmd, 0x00,0x00,0x00,0x00,0x00,0x00]

  move: (direction, duration) ->
    return if @busy
    @_log "Move #{direction} for #{duration}"
    @busy = true
    ready = Q.defer()
    @sendCommand direction
    setTimeout =>
      @sendCommand 'STOP'
      @busy = false
      ready.resolve()
    , duration
    ready.promise

  fire: ->
    return if @busy
    @_log "Firing!"
    @busy = true
    ready = Q.defer()
    @sendCommand 'FIRE'
    setTimeout =>
      @busy = false
      ready.resolve()
    , @config.FIRING_TIME
    ready.promise

  pause: (duration) ->
    return if @busy
    @_log "Pause for #{duration}"
    @busy = true
    ready = Q.defer()
    setTimeout =>
      @busy = false
      ready.resolve()
    , duration
    ready.promise

  reset: ->
    @_log 'Resetting...'
    @verticalAngle = @config.MIN_VERTICAL_ANGLE
    @horizontalAngle = @config.MIN_HORIZONTAL_ANGLE
    @sequence [
      "DOWN #{@config.FULL_PITCH_TIME}"
      "LEFT #{@config.FULL_TURN_TIME}"
    ]

  sequence: (commandSequence) ->
    return Q.defer().resolve().promise if !commandSequence || commandSequence.length == 0
    parsedSequence = (@parseCommand(cmd) for cmd in commandSequence)
    ready = parsedSequence.shift()()
    while next = parsedSequence.shift()
      do ->
        cmd = next
        ready = ready.then cmd
    ready
  
  parseCommand: (cmd) ->
    [command, duration] = cmd.split /\s/
    duration = parseInt(duration, 10) if duration
    if command == 'FIRE'
      => @fire()
    else if command == 'RESET'
      => @reset()
    else if command == 'PAUSE'
      => @pause duration
    else if command in ['UP', 'DOWN', 'LEFT', 'RIGHT']
      => @move command, duration
    else
      throw "#{command} is not a valid command"
  
  turnBy: (angle) ->
    direction = if angle > 0 then 'RIGHT' else 'LEFT'
    duration = Math.round(Math.abs(angle) * @config.HORIZONTAL_TURN_RATE)
    @horizontalAngle += angle
    @_log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
    
  pitchBy: (angle) ->
    direction = if angle > 0 then 'UP' else 'DOWN'
    duration = Math.round(Math.abs(angle) * @config.VERTICAL_TURN_RATE)
    @verticalAngle += angle
    @_log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
  
  pointTo: (horizontalAngle, verticalAngle) ->
    horizontalAngle = @config.MAX_HORIZONTAL_ANGLE if horizontalAngle > @config.MAX_HORIZONTAL_ANGLE
    horizontalAngle = @config.MIN_HORIZONTAL_ANGLE if horizontalAngle < @config.MIN_HORIZONTAL_ANGLE
    verticalAngle = @config.MAX_VERTICAL_ANGLE if verticalAngle > @config.MAX_VERTICAL_ANGLE
    verticalAngle = @config.MIN_VERTICAL_ANGLE if verticalAngle < @config.MIN_VERTICAL_ANGLE
    @pitchBy(verticalAngle - @verticalAngle).then(=> @turnBy(horizontalAngle - @horizontalAngle))
  
  zero: ->
    @reset().then(=> @pointTo(0,0))

  fireAt: (horizontalAngle, verticalAngle) ->
    @pointTo(horizontalAngle, verticalAngle)
      .then(=> @fire())
      
  _log: (text...) ->
    console.log text... if @config.log
    
module.exports = MissileLauncher
