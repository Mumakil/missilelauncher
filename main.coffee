MissileLauncher = require './lib/missilelauncher'

launcherPaths = MissileLauncher.findLaunchers()

launchers = (new MissileLauncher(path) for path in launcherPaths)

for l in launchers
  do =>
    launcher = l
    launcher.zero().then -> launcher.fireAt(30, 20).then -> launcher.fireAt(-30, 10)
