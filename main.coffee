MissileLauncher = require './lib/missilelauncher'

launcherPaths = MissileLauncher.findLaunchers()

launchers = (new MissileLauncher(path: path) for path in launcherPaths)

for l in launchers
  do =>
    launcher = l
    launcher.zero()