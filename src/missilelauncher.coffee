HID = require 'node-hid'
Q = require 'q'

extend = (dest, source...) ->
  for src in source when typeof src == 'object'
    for key in Object.keys src
      if typeof src[key] == 'object'
        dest[key] = extend {}, dest[key], src[key]
      else
        dest[key] = src[key]
  dest

# Default config for a DC Thunder missile launcher
defaultConfig = 
  # time limits
  time:
    # milliseconds it takes to turn the turret from side to side
    fullTurn: 5465 # 5500
    # milliseconds it takes to turn the turret from bottom to top
    fullPitch: 835 # 1100
    # millisencods it takes to fire
    fire: 3500
  
  # angle limits
  angle:
    horizontal:
      max: 138
      min: -138
    vertical: 
      max: 28
      min: -6
  
  log: true

commands =
  DOWN    : 0x01
  UP      : 0x02
  LEFT    : 0x04
  RIGHT   : 0x08
  FIRE    : 0x10
  STOP    : 0x20

class Missilelauncher

  @findLaunchers: ->
    devices = HID.devices()
    match = (device) ->
      device.vendorId == Missilelauncher.vendorId and device.productId == Missilelauncher.productId
    launchers = (device.path for device in devices when match(device))

  @defaultConfig: defaultConfig
  @vendorId: 0x2123
  @productId: 0x1010
  @commands: commands

  constructor: (options) ->
    config = extend {}, Missilelauncher.defaultConfig, options.config
    @config = extend config, 
      angle:
        vertical:
          full: config.angle.vertical.max - config.angle.vertical.min
          rate: config.time.fullPitch / (config.angle.vertical.max - config.angle.vertical.min)
        horizontal: 
          full: config.angle.horizontal.max - config.angle.horizontal.min
          rate: config.time.fullTurn / (config.angle.horizontal.max - config.angle.horizontal.min)
    if options.device
      @device = options.device
    else
      @device = new HID.HID(options.path)
    @busy = false
    @direction = {}

  _sendCommand: (command) ->
    return false unless typeof command == 'string'
    cmd = Missilelauncher.commands[command.toUpperCase()]
    @device.write [0x02, cmd, 0x00,0x00,0x00,0x00,0x00,0x00]

  move: (direction, duration) ->
    return if @busy
    @_log "Move #{direction} for #{duration}"
    @busy = true
    ready = Q.defer()
    @_sendCommand direction
    setTimeout =>
      @_sendCommand 'STOP'
      @busy = false
      ready.resolve()
    , duration
    ready.promise

  fire: ->
    return if @busy
    @_log "Firing!"
    @busy = true
    ready = Q.defer()
    @_sendCommand 'FIRE'
    setTimeout =>
      @busy = false
      ready.resolve()
    , @config.time.fire
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
    @direction = 
      horizontal: @config.angle.horizontal.min
      vertical: @config.angle.vertical.min
    @sequence [
      "DOWN #{@config.time.fullPitch}"
      "LEFT #{@config.time.fullTurn}"
    ]

  sequence: (commandSequence) ->
    return Q.defer().resolve().promise if !commandSequence or commandSequence.length == 0
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
  
  _limitTurning: (angle, direction) ->
    #console.log 'LIMIT TURNING', angle, direction, @direction[direction]
    if @direction[direction] + angle > @config.angle[direction].max
      @config.angle[direction].max - @direction[direction]
    else if @direction[direction] + angle < @config.angle[direction].min
      @config.angle[direction].min - @direction[direction]
    else
      angle
  
  turnBy: (angle) ->
    direction = if angle > 0 then 'RIGHT' else 'LEFT'
    angle = @_limitTurning(angle, 'horizontal')
    duration = @timeToTurn(horizontal: angle, null, false)
    @direction.horizontal += angle
    @_log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
    
  pitchBy: (angle) ->
    direction = if angle > 0 then 'UP' else 'DOWN'
    angle = @_limitTurning(angle, 'vertical')
    duration = @timeToTurn(vertical: angle, null, false)
    @direction.vertical += angle
    @_log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
  
  pointTo: (horizontal, vertical) ->
    if typeof horizontal == 'object'
      {horizontal, vertical} = horizontal
    @pitchBy(vertical - @direction.vertical)
      .then(=> @turnBy(horizontal - @direction.horizontal))
  
  timeToTurn: (horizontal, vertical, absolute = true) ->
    if horizontal? and typeof horizontal == 'object'
      {horizontal, vertical} = horizontal
    time = 0
    if horizontal?
      horizontal -= @direction.horizontal if absolute
      horizontal = @_limitTurning(horizontal, 'horizontal')
      time += Math.round(Math.abs(horizontal) * @config.angle.horizontal.rate)
    if vertical?
      vertical -= @direction.vertical if absolute
      vertical = @_limitTurning(vertical, 'vertical')
      time += Math.round(Math.abs(vertical) * @config.angle.vertical.rate)
    #console.log 'TIME TO TURN', (if absolute then 'to' else ''), horizontal, vertical, time
    time
  
  zero: ->
    @reset().then(=> @pointTo(0,0))

  fireAt: (horizontal, vertical) ->
    @pointTo(horizontal, vertical)
      .then(=> @fire())
      
  _log: (text...) ->
    console.log text... if @config.log
    
module.exports = Missilelauncher
