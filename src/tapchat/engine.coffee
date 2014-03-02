#
# engine.coffee
#
# Copyright (C) 2012-2013 Eric Butler <eric@codebutler.com>
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
Gzippo        = require('gzippo')
Eco           = require('eco')

Log          = require './log'
Config       = require './config'
User         = require './user'
BacklogDB    = require './backlog_db'
SessionStore = require './session_store'

{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class Engine
  constructor: (config, callback) ->
    @users = []

    @port = config.port

    @db = new BacklogDB =>
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

    sessionChecker = (req, res, next) =>
      checkSession req.cookies.session, (session, user) =>
        res.clearCookie('session', {secure: true, path: '/'}) unless user?
        res.clearCookie('session', {secure: true, path: '/chat'}) unless user?
        next()

    @app.use(Express.logger()) if Log.level == 'silly'
    @app.use(Express.cookieParser())
    @app.use(Express.bodyParser())
    @app.use(Express.methodOverride())
    @app.use(Passport.initialize())
    @app.use(sessionChecker)
    @app.use(Express.static(__dirname + '/../../web'))
    @app.use(Gzippo.compress())

    @app.set 'views', __dirname + '/../../web'
    @app.engine 'eco', (path, options, fn) ->
      Fs.readFile path, 'utf8', (err, str) ->
        return fn(err) if err
        str = Eco.render(str, options)
        fn(null, str)

    checkSession = (sessionId, callback) =>
      session = @sessions.get(sessionId)

      # Invalid Session ID.
      return callback(null) unless session?

      user = @users[session.uid]

      # Invalid User ID.
      unless user?
        @sessions.destroy(sessionId)
        return callback(null, null)

      return callback(session, user)

    restrict = (req, res, next) =>
      checkSession req.cookies.session, (session, user) =>
        unless user
          res.send(401, 'Unauthorized')
          return
        req.session = session
        req.user = user
        return next()

    restrict_admin = (req, res, next) ->
      restrict req, res, =>
        unless req.user.is_admin
          res.send(401, 'Unauthorized')
        else
          return next()

    @app.post '/chat/login', (req, res) =>
      req.body.username = req.body.email if req.body.email?
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
            user:
              id: user.uid
              name: user.name
              is_admin: user.is_admin == 1

          res.json response

      auth(req, res)

    @app.post '/chat/logout', restrict, (req, res) =>
      @sessions.destroy(req.cookies.session)
      res.json
        success: true

    @app.post '/chat/change-password', restrict, (req, res) =>
      oldpassword = req.body.oldpassword
      newpassword = req.body.newpassword

      unless newpassword? and newpassword.length >= 8
        res.json
          success: false
          message: 'New password is too short.',
          400
        return

      @db.selectUser req.session.uid, (userInfo) =>
        unless PasswordHash.verify(oldpassword, userInfo.password)
          res.json
            success: false
            message: 'Incorrect old password.',
            400
          return

        @db.updateUser req.session.uid,
          password_hash: PasswordHash.generate(newpassword),
          (row) =>
            res.json
              success: true

    @app.get '/chat/backlog', restrict, (req, res) =>
      user = req.user
      bid = req.param('bid')
      cid = req.param('cid')
      if bid and cid
        num      = req.param('num') || 150
        beforeid = req.param('beforeid')
        @db.selectEventsRange cid, bid, num, beforeid, (rows) ->
          rows = ((merge
            eid:  row.eid,
            time: row.created_at,
            JSON.parse(row.data)) for row in rows)
          res.json(rows)
      else
        events = []
        user.getBacklog ((event) =>
          events.push(user.prepareMessage(event))
        ), ->
          res.json(events)

    @app.get '/admin/users', restrict_admin, (req, res) =>
      user = req.user
      users = (user.asJson() for uid,user of @users)
      res.json(users)

    @app.post '/admin/users', restrict_admin, (req, res) =>
      name     = req.body.name
      password = req.body.password
      isAdmin  = req.body.is_admin == 'true'

      @db.insertUser name, PasswordHash.generate(password), isAdmin, (row) =>
        user = @addUser(row)
        res.json
          success: true
          user: user.asJson()

    @app.put '/admin/users/:user_id', restrict_admin, (req, res) =>
      user = @users[req.param('user_id')]
      user.edit
        password_hash: PasswordHash.generate(req.body.password)
        is_admin: if req.body.is_admin == 'true' then 1 else 0,
        =>
          res.json
            success: true

    @app.delete '/admin/users/:user_id', restrict_admin, (req, res) =>
      user = @users[req.param('user_id')]
      @deleteUser user, =>
        for session_id, session of @sessions.all()
          if session.uid == user.id
            @sessions.destroy(session_id)
        res.json
          success: true

    @web = Https.createServer
      key:  Fs.readFileSync(Config.getCertFile())
      cert: Fs.readFileSync(Config.getCertFile()),
      @app

    @web.addListener 'upgrade', (req, socket, head) =>
      req.method = 'UPGRADE' # Prevent any matching GET handlers from running
      res = new Http.ServerResponse(req)
      res.assignSocket(socket)
      @app.handle req, res, =>
        restrict req, res, =>
          ws = new WebSocket(req, socket, head)
          req.user.addClient(ws, req.param('inband', false))

    @web.listen port, '::', =>
      console.log "\nTapChat ready at https://localhost:#{port}\n"
      callback(this) if callback

  addUser: (userInfo) ->
    user = new User(this, userInfo)
    @users[user.id] = user

  deleteUser: (user, cb) ->
    user.delete =>
      @users.splice(@users.indexOf(user), 1)
      cb() if cb

module.exports = Engine
