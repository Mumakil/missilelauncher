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

FULL_TURN_TIME = 5800
FULL_PITCH_TIME = 1100
FIRING_TIME = 3500

module.exports = class MissileLauncher

  @findLaunchers: ->
    devices = HID.devices()
    match = (device) ->
      device.vendorId == VENDOR_ID && device.productId == PRODUCT_ID
    launchers = device.path for device in devices when match(device)

  constructor: (path) ->
    @launcher = new HID.HID(path)
    @moving = false

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
    , FIRING_TIME
    ready.promise

  reset: ->
    @sequence [
      "LEFT #{FULL_TURN_TIME}"
      "DOWN #{FULL_PITCH_TIME}"
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
          console.log "Sequence: MOVE #{next.command}!"
          @move next.command, next.duration
      promise.then =>
        @sequentially(commandSequence).then -> ready.resolve()
    else
      ready.resolve()
    ready.promise
