missilelauncher.js
==================

[![Build Status](https://travis-ci.org/Mumakil/missilelauncher.png)](https://travis-ci.org/Mumakil/missilelauncher)

Small node library to control a DC Thunder nerf missile launcher.

Quickstart
==========

* Connect your USB missile launcher to your computer
* Run `coffee main.coffee`

Usage
=====

Missilelauncher relies heavily on [Q](https://github.com/kriskowal/q) for 
asynchronous behavior. If you don't know how promises work, check the github page.

```
# Start by requiring the module.
Missilelauncher = require 'missilelauncher'

# List all available devices with 
paths = Missilelauncher.findLaunchers()

# Create new launcher instance with
launcher = new Missilelauncher path: paths[0]

# Launcher does not know where it points at when it starts, so
# reset and point to (0,0), or straight forward.
launcher.zero().then ->

  # After reset you can start firing at something
  # (90 degrees right, 10 up)
  launcher.fireAt(90, 10).then -> 

    # ...or command it in a sequence
    # (numbers are milliseconds of turning time)
    launcher.sequence [
      'UP 100'
      'LEFT 2000'
      'PAUSE 500'
      'FIRE'
    ]
  
```

Dependencies
------------

* node-hid
* Q

Thanks
------

Big thanks to https://github.com/codedance/Retaliation for instructions on how the usb api works.

Author
------

Otto Vehviläinen [@Mumakil](http://twitter.com/Mumakil)