# TapChat Server

More info here soon.

## Setup

Roughly:

	$ npm install
	
	$ ./bin/hash-password your_password
	sha1$sQ82I5t7$1$cbe54922c1d1b2afb9250c6d5a38d80140f1d561
	
	$ export TAPCHAT_PASS='sha1$sQ82I5t7$1$cbe54922c1d1b2afb9250c6d5a38d80140f1d561'
	$ export TAPCHAT_PORT=1234
	
	$ ./bin/tapchat-server

nodejitsu:

	$ jitsu apps create
    $ jitsu env set TAPCHAT_PASS 'sha1$sQ82I5t7$1$cbe54922c1d1b2afb9250c6d5a38d80140f1d561
    $ jitsu env set TAPCHAT_PORT 80
    $ jitsu deploy