HID = require 'node-hid'
MissileLauncher = require './missilelauncher'

launcherPaths = MissileLauncher.findLaunchers()

launchers = new MissileLauncher path for path in launcherPaths

for launcher in launchers
  launcher.sequence [
    'RIGHT 2500'
    'UP 550'
    'FIRE'
    # 'FIRE'
    # 'FIRE'
    # 'FIRE'
    'RESET'
  ]
