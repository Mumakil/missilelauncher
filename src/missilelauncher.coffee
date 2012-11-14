HID = require 'node-hid'
Q = require 'q'

# Recursively copy sources' properties to dest
extend = (dest, sources...) ->
  for src in sources when typeof src == 'object'
    for key in Object.keys src
      if typeof src[key] == 'object'
        dest[key] = extend {}, dest[key], src[key]
      else
        dest[key] = src[key]
  dest

# Parses either {horizontal: XX, vertical: XX} or plain arguments
# into horizontal and vertical angles
parseAngles = (args) ->
  if args[0]? and typeof args[0] == 'object'
    {horizontal, vertical} = args[0]
  else
    [horizontal, vertical] = args
  [horizontal, vertical]

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

# Octal commands to send to the HID device
commands =
  DOWN    : 0x01
  UP      : 0x02
  LEFT    : 0x04
  RIGHT   : 0x08
  FIRE    : 0x10
  STOP    : 0x20

class Missilelauncher

  # Finds all attached missilelaunchers that match the 
  # vendorId and productId and returns an array of
  # hid paths
  @findLaunchers: ->
    devices = HID.devices()
    match = (device) ->
      device.vendorId == Missilelauncher.vendorId and device.productId == Missilelauncher.productId
    launchers = (device.path for device in devices when match(device))

  # Model identifiers
  @vendorId: 0x2123
  @productId: 0x1010
  
  @commands: commands
  @defaultConfig: defaultConfig

  # Creates a new missilelauncer. options can have the following
  # properties:
  # - config: will extend the default
  # - path: path to the usb device
  # - device: an object that has a write method that can take the
  #           raw usb commands 
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

  # Kind of privateish method to send the raw usb commands to
  # the device. Uses Missilelauncher.commands to translate
  # strings into commands.
  _sendCommand: (command) ->
    return false unless typeof command == 'string'
    cmd = Missilelauncher.commands[command.toUpperCase()]
    @device.write [0x02, cmd, 0x00,0x00,0x00,0x00,0x00,0x00]

  # Low level move command to turn the turret to a direction for
  # the specified duration in ms. Returns a promise that
  # resolves after movement. Direction must be either
  # 'UP', 'DOWN', 'LEFT' or 'RIGHT'.
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

  # Fires immediately one missile. Returns a promise that resolves
  # after the firing routine has been completed.
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

  # Pauses the launcer for specified time. Mostly useful when 
  # chained with other commands. Returns a promise that resolves
  # after duration.
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

  # Resets the turret to point as far down and left as possible.
  # The usb protocol does not tell where the turret is pointing at,
  # so we must turn the turret to a known position before it's 
  # reasonable to issue commands. Returns a promise that resolves
  # after reset is complete.
  reset: ->
    @_log 'Resetting...'
    @direction = 
      horizontal: @config.angle.horizontal.min
      vertical: @config.angle.vertical.min
    @sequence [
      "DOWN #{@config.time.fullPitch}"
      "LEFT #{@config.time.fullTurn}"
    ]

  # Runs a sequence of commands. Commands are an array of strings
  # in the format that parseCommand can use. The commands are executed
  # one after another and the returned promise resolves after all of
  # them are executed.
  sequence: (commandSequence) ->
    return Q.defer().resolve().promise if !commandSequence or commandSequence.length == 0
    parsedSequence = (@parseCommand(cmd) for cmd in commandSequence)
    ready = parsedSequence.shift()()
    while next = parsedSequence.shift()
      do ->
        cmd = next
        ready = ready.then cmd
    ready
  
  # Parses a string command and returns a function that can be executed to
  # run the command. All commands return a promise that resolves after the
  # command has completed. Supported commands are:
  # - '[UP|DOWN|LEFT|RIGHT] {duration}', for example 'UP 100'
  # - 'FIRE'
  # - 'PAUSE {duration}', for example 'PAUSE 100'
  # - 'RESET'
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
  
  # Used to limit turning to the configured limits so that we don't 
  # lose the calibrated direction.
  _limitTurning: (angle, direction) ->
    if @direction[direction] + angle > @config.angle[direction].max
      @config.angle[direction].max - @direction[direction]
    else if @direction[direction] + angle < @config.angle[direction].min
      @config.angle[direction].min - @direction[direction]
    else
      angle
  
  # Turns the turret horizontally by angle degrees. Returns a promise
  # that resolves after the movement is complete. Does not turn past
  # configured limits.
  turnBy: (angle) ->
    direction = if angle > 0 then 'RIGHT' else 'LEFT'
    angle = @_limitTurning(angle, 'horizontal')
    duration = @timeToTurn(horizontal: angle, null, false)
    @direction.horizontal += angle
    @_log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
  
  # Turns the turret vertically by angle degrees. Returns a promise
  # that resolves after the movement is complete. Does not turn past
  # configured limits.
  pitchBy: (angle) ->
    direction = if angle > 0 then 'UP' else 'DOWN'
    angle = @_limitTurning(angle, 'vertical')
    duration = @timeToTurn(vertical: angle, null, false)
    @direction.vertical += angle
    @_log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
  
  # Points the turret to spherical coordinates horizontal, vertical.
  # The first argument can also be an object specifying the coordinates
  # {horizontal: 0, vertical: 0}. Respects the configured limits. Returns
  # a promise that resolves after the movement is complete.
  pointTo: (horizontal, vertical) ->
    [horizontal, vertical] = parseAngles(arguments)
    @pitchBy(vertical - @direction.vertical)
      .then(=> @turnBy(horizontal - @direction.horizontal))
  
  # Calculates the time it takes to point to spherical coordinates 
  # horizontal, vertical. The first argument can also be an object 
  # specifying the coordinates {horizontal: 0, vertical: 0}. Respects
  # the configured limits.
  timeToTurn: (horizontal, vertical, absolute = true) ->
    [horizontal, vertical] = parseAngles(arguments)
    time = 0
    if horizontal?
      horizontal -= @direction.horizontal if absolute
      horizontal = @_limitTurning(horizontal, 'horizontal')
      time += Math.round(Math.abs(horizontal) * @config.angle.horizontal.rate)
    if vertical?
      vertical -= @direction.vertical if absolute
      vertical = @_limitTurning(vertical, 'vertical')
      time += Math.round(Math.abs(vertical) * @config.angle.vertical.rate)
    time
  
  # Points the turret straight forward. Runs the reset manouver and 
  # resets the internal directions too. Returns a promise that resolves
  # after the routine is complete.
  zero: ->
    @reset().then(=> @pointTo(0,0))

  # Fires at the specified coordinates. Coordinates can be in the same
  # format as with pointTo. Returns a promise that resolves after
  # the firing routine has completed.
  fireAt: (horizontal, vertical) ->
    @pointTo(horizontal, vertical)
      .then(=> @fire())
  
  # Tells whether the turret can fire at the specified spherical coordinates.
  canFireAt: (horizontal, vertical) ->
    [horizontal, vertical] = parseAngles(arguments)
    (horizontal <= @config.angle.horizontal.max and 
      horizontal >= @config.angle.horizontal.min and 
      vertical <= @config.angle.vertical.max and 
      vertical >= @config.angle.vertical.min)
  
  _log: (text...) ->
    console.log text... if @config.log
    
module.exports = Missilelauncher
