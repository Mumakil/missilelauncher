HID = require 'node-hid'
MissileLauncher = require './missilelauncher'

launcher = new MissileLauncher MissileLauncher.findLaunchers()[0]
launcher.sequence [
  'RIGHT 2500'
  'UP 550'
  'FIRE'
  'FIRE'
  'FIRE'
  'FIRE'
  'RESET'
]
