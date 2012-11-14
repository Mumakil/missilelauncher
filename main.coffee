MissileLauncher = require './src/missilelauncher'

launcherPaths = MissileLauncher.findLaunchers()

launchers = (new MissileLauncher(path: path) for path in launcherPaths)

for l in launchers
  do =>
    launcher = l
    launcher.zero()
      # .then(-> launcher.sequence ['UP 100', 'LEFT 300'])
      # .then(-> launcher.sequence ['DOWN 100', 'RIGHT 300'])
      .then(-> launcher.fireAt(30, 15))
      .then(-> launcher.fireAt(-45, 5))
      .then(-> launcher.fireAt(10, 25))
      .then(-> launcher.pointTo(0,0))