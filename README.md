# TapChat: Modern IRC Client

Stay connected with your favorite channels without draining your phone's battery. Scroll back to catch up on what you've missed, and receive push notifications1 when someone mentions or messages you.

 * [Website](http://tapchatapp.com/)
 * [Android App](https://github.com/tapchat/tapchat-android)

Installing
----------

### Install into user directory

    $ npm install
    $ ./bin/tapchat start

### Install system-wide

    $ sudo npm install -g
    $ tapchat start
    
Access the web interface by visiting `https://your_ip_address:8067`. Note that only secure HTTPS is supported. Select the option to save the automatically-generated certificate into your browser after verifying the fingerprint matches.

If you have any problems, you can start tapchat in debug mode:

    $ tapchat start -fv

Authors
-------

 * [Eric Butler](https://twitter.com/codebutler)

Contributing
------------

This repository is set up with [BitHub](https://whispersystems.org/blog/bithub/), so you can make money for committing to TapChat. The current BitHub price for an accepted pull request is:

[![Current BitHub Price](https://tapchat-bithub.herokuapp.com/v1/status/payment/commit/)](https://tapchat-bithub.herokuapp.com/)

License
-------

    Copyright (C) 2014 Eric Butler

	This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
