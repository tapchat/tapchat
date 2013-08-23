#
# engine.coffee
#
# Copyright (C) 2012 Eric Butler <eric@codebutler.com>
#
# This file is part of TapChat.
#
# TapChat is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# TapChat is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with TapChat.  If not, see <http://www.gnu.org/licenses/>.

Path          = require('path')
Fs            = require('fs')
WorkingQueue  = require('capisce').WorkingQueue
Http          = require('http')
Https         = require('https')
Passport      = require('passport')
LocalStrategy = require('passport-local').Strategy
Express       = require('express')
Url           = require('url')
WebSocket     = require('faye-websocket')
PasswordHash  = require('password-hash')
CoffeeScript  = require('coffee-script')
Util          = require('util')
Crypto        = require('crypto')
_             = require('underscore')
DataBuffer    = require('buffer').Buffer
Gzippo        = require('gzippo')
Eco           = require('eco')

Log          = require './log'
Config       = require './config'
User         = require './user'
BacklogDB    = require './backlog_db'
PushClient   = require './push_client'
SessionStore = require './session_store'

{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class Engine
  constructor: (config, initialUser, callback) ->
    @users = []

    @port = config.port

    @pushId  = config.push_id
    @pushKey = new DataBuffer(config.push_key, 'base64')
    @pushClient = new PushClient(this)

    @db = new BacklogDB =>
      if initialUser
        @db.insertUser initialUser.name, initialUser.password, true, =>
          @finishLoading(callback)
      else
        @finishLoading(callback)

  finishLoading: (callback) ->
    @startServer(@port, callback)
    @db.selectUsers (users) =>
      @addUser userInfo for userInfo in users

  startServer: (port, callback) ->
    Passport.use new LocalStrategy (username, password, done) =>
      @db.selectUserByName username, (userInfo) =>
        return done(null, false, message: 'Invalid username') unless userInfo?
        unless PasswordHash.verify(password, userInfo.password)
          return done(null, false, message: 'Invalid password')
        done(null, userInfo)
  
    @sessions = new SessionStore(Path.join(Config.getDataDirectory(), 'sessions.json'))

    @app = Express()

    @app.use(Express.logger()) if Log.level == 'silly'
    @app.use(Express.cookieParser())
    @app.use(Express.bodyParser())
    @app.use(Express.methodOverride())
    @app.use(Passport.initialize())
    @app.use(Express.static(__dirname + '/../../web'))
    @app.use(Gzippo.compress())

    @app.set 'views', __dirname + '/../../web'
    @app.engine 'eco', (path, options, fn) ->
      Fs.readFile path, 'utf8', (err, str) ->
        return fn(err) if err
        str = Eco.render(str, options)
        fn(null, str)

    @app.get '/', (req, res) =>
      res.render 'index.html.eco',
        layout:          false

    @app.post '/login', (req, res) =>
      req.body.username = 'user' unless req.body.username?
      auth = Passport.authenticate 'local', (err, user, info) =>
        return next(err) if err

        unless user
          response =
            success: false
            message: info.message
          res.json response, 401

        if user
          sessionId = Crypto.randomBytes(32).toString('hex')
          @sessions.set(sessionId, {uid: user.uid})
          response =
            success: true
            session: sessionId
          res.json response

      auth(req, res)

    @app.get '/chat/backlog', (req, res) =>
      unless @sessions.get(req.cookies.session)
        req.socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n');
        return next()

      events = []

      @getBacklog ((event) =>
        events.push(@prepareMessage(event))
      ), ->
        res.json(events)

    @web = Https.createServer
      key:  Fs.readFileSync(Config.getCertFile())
      cert: Fs.readFileSync(Config.getCertFile()),
      @app

    @web.addListener 'upgrade', (request, socket, head) =>
      request.method = 'UPGRADE' # Prevent any matching GET handlers from running
      res = new Http.ServerResponse(request)
      @app.handle request, res, =>
        session = @sessions.get(request.cookies.session)
        if session
          console.log 'got session', session, @users
          ws = new WebSocket(request, socket, head)
          user = @users[session.uid]
          user.inbandBacklog = request.param('inband', false)
          user.addClient(ws)
          Log.debug 'websocket client: connected'
        else
          Log.info 'websocket client: unauthorized'
          request.socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n')

    @web.listen port, =>
      console.log "\nTapChat ready at https://localhost:#{port}\n"
      callback(this) if callback

  addUser: (userInfo) ->
    user = new User(this, userInfo)
    @users[user.id] = user

module.exports = Engine
