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

CONSTANTS = C = 
  # Milliseconds it takes to turn the turret from side to side
  FULL_TURN_TIME: 5500
  # Milliseconds it takes to turn the turret from bottom to top
  FULL_PITCH_TIME: 1100
  # Millisencods it takes to fire
  FIRING_TIME: 3500

  # Full angle in degrees that the turret turns horizontally
  FULL_HORIZONTAL_ANGLE: 330
  # Full angle in dedgrees that the turret turns vertically
  FULL_VERTICAL_ANGLE: 35
  
  # Angle limits
  MAX_HORIZONTAL_ANGLE: 165
  MIN_HORIZONTAL_ANGLE: -165
  MAX_VERTICAL_ANGLE: 30
  MIN_VERTICAL_ANGLE: -5
  
CONSTANTS.VERTICAL_TURN_RATE = C.FULL_PITCH_TIME / C.FULL_VERTICAL_ANGLE
CONSTANTS.HORIZONTAL_TURN_RATE = C.FULL_TURN_TIME / C.FULL_HORIZONTAL_ANGLE

class MissileLauncher

  @findLaunchers: ->
    devices = HID.devices()
    match = (device) ->
      device.vendorId == VENDOR_ID && device.productId == PRODUCT_ID
    launchers = device.path for device in devices when match(device)

  @CONSTANTS: CONSTANTS

  constructor: (path) ->
    @launcher = new HID.HID(path)
    @moving = false
    @verticalAngle = undefined
    @horizontalAngle = undefined

  sendCommand: (command) ->
    cmd = LAUNCHER_COMMANDS[command]
    @launcher.write [0x02, cmd, 0x00,0x00,0x00,0x00,0x00,0x00]

  move: (direction, duration) ->
    return if @moving
    @moving = true
    ready = Q.defer()
    @sendCommand direction
    setTimeout =>
      @sendCommand 'STOP'
      @moving = false
      ready.resolve()
    , duration
    ready.promise

  fire: ->
    return if @moving
    @moving = true
    ready = Q.defer()
    @sendCommand 'FIRE'
    setTimeout =>
      @moving = false
      ready.resolve()
    , C.FIRING_TIME
    ready.promise

  reset: ->
    @verticalAngle = C.MIN_VERTICAL_ANGLE
    @horizontalAngle = C.MIN_HORIZONTAL_ANGLE
    @sequence [
      "DOWN #{C.FULL_PITCH_TIME}"
      "LEFT #{C.FULL_TURN_TIME}"
    ]

  sequence: (commands) ->
    parsedCommands = for commandString in commands
      [command, duration] = commandString.split /\s/
      command: command, duration: (if duration then parseInt(duration, 10) else undefined)
    ready = Q.defer()
    @sequentially(parsedCommands).then -> ready.resolve()
    ready.promise

  sequentially: (commandSequence) ->
    ready = Q.defer()
    next = commandSequence.shift()
    if next
      promise =
        if next.command == 'FIRE'
          console.log "Sequence: FIRE!"
          @fire()
        else if next.command == 'RESET'
          console.log "Sequence: RESET!"
          @reset()
        else
          console.log "Sequence: MOVE #{next.command} for #{next.duration}!"
          @move next.command, next.duration
      promise.then =>
        @sequentially(commandSequence).then -> ready.resolve()
    else
      ready.resolve()
    ready.promise
    
  turnBy: (angle) ->
    direction = if angle > 0 then 'RIGHT' else 'LEFT'
    duration = Math.round(Math.abs(angle) * C.HORIZONTAL_TURN_RATE)
    @horizontalAngle += angle
    console.log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
    
  pitchBy: (angle) ->
    direction = if angle > 0 then 'UP' else 'DOWN'
    duration = Math.round(Math.abs(angle) * C.VERTICAL_TURN_RATE)
    @verticalAngle += angle
    console.log "Turn", direction, 'by', angle, 'deg in', duration, 'ms'
    @move(direction, duration)
  
  pointTo: (horizontalAngle, verticalAngle) ->
    horizontalAngle = C.MAX_HORIZONTAL_ANGLE if horizontalAngle > C.MAX_HORIZONTAL_ANGLE
    horizontalAngle = C.MIN_HORIZONTAL_ANGLE if horizontalAngle < C.MIN_HORIZONTAL_ANGLE
    verticalAngle = C.MAX_VERTICAL_ANGLE if verticalAngle > C.MAX_VERTICAL_ANGLE
    verticalAngle = C.MIN_VERTICAL_ANGLE if verticalAngle < C.MIN_VERTICAL_ANGLE
    ready = Q.defer()
    @pitchBy(verticalAngle - @verticalAngle).then =>
      @turnBy(horizontalAngle - @horizontalAngle).then => ready.resolve()
    ready.promise
  
  zero: ->
    ready = Q.defer()
    @reset().then => @pointTo(0,0).then -> ready.resolve()
    ready.promise

  fireAt: (horizontalAngle, verticalAngle) ->
    ready = Q.defer()
    @pointTo(horizontalAngle, verticalAngle).then =>
      @fire().then -> ready.resolve()
    ready.promise

module.exports = MissileLauncher
