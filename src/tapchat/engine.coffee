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

Log          = require './log'
Base64       = require '../base64'
Config       = require './config'
B            = require './message_builder'
Buffer       = require './buffer'
Connection   = require './connection'
BacklogDB    = require './backlog_db'
PushClient   = require './push_client'
SessionStore = require './session_store'

{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class Engine
  constructor: (config, callback) ->
    @connections = []
    @clients     = []

    @password = config.password
    @port     = config.port

    throw 'No password set!' unless PasswordHash.isHashed(@password)

    @pushId  = config.push_id
    @pushKey = new DataBuffer(config.push_key, 'base64')
    @pushClient = new PushClient(this)

    @db = new BacklogDB this, =>
      @startServer(@port, callback)

      @db.selectConnections (conns) =>
        @addConnection connInfo for connInfo in conns

  startServer: (port, callback) ->
    Passport.use new LocalStrategy (username, password, done) =>
      unless PasswordHash.verify(password, @password)
        return done(null, false, message: 'Invalid password')
      done(null, {})
  
    @sessions = new SessionStore(Path.join(Config.getDataDirectory(), 'sessions.json'))

    @app = Express.createServer
      key:  Fs.readFileSync(Config.getCertFile())
      cert: Fs.readFileSync(Config.getCertFile())

    # @app.use(Express.logger()) # FIXME: Only if verbose
    @app.use(Express.cookieParser())
    @app.use(Express.bodyParser())
    @app.use(Express.methodOverride())
    @app.use(Passport.initialize())
    @app.use(Express.static(__dirname + '/../../web'))
    @app.use(Gzippo.compress())

    @app.set 'views', __dirname + '/../../web'
    @app.set 'view engine', 'html.eco'
    @app.register('.html.eco', require('eco'))
    @app.get '/', (req, res) =>
      res.render 'index',
        layout:          false,
        num_clients:     @clients.length
        num_connections: @connections.length

    @app.post '/login', (req, res) =>
      req.body.username = 'ignore' # No usernames yet
      auth = Passport.authenticate 'local', (err, user, info) =>
        return next(err) if err

        unless user
          response =
            success: false
            message: info.message
          res.json response, 401

        if user
          sessionId = Crypto.randomBytes(32).toString('hex')
          @sessions.set(sessionId, {}) # Not currently storing anything in the session
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

    @app.addListener 'upgrade', (request, socket, head) =>
      request.method = 'UPGRADE' # Prevent any matching GET handlers from running
      res = new Http.ServerResponse(request)
      @app.handle request, res, =>
        @inbandBacklog = request.param('inband', false)
        if @sessions.get(request.cookies.session)
          ws = new WebSocket(request, socket, head)
          Log.info 'websocket client: connected'
          @addClient(ws)
        else
          console.log('unauthorized')
          request.socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n');

    @app.listen port, =>
      console.log "\nTapChat ready at https://localhost:#{port}\n"
      callback(this) if callback

  addClient: (client) ->
    client.sendQueue = new WorkingQueue(1)
    @clients.push(client)

    client.onmessage = (event) =>
      message = JSON.parse(event.data)

      unless message._reqid
        Log.error 'Missing _reqid, ignoring message', event.data
        return

      Log.silly 'Got message:', event.data

      callback = (reply) =>
        @send client,
          _reqid: message._reqid
          msg:    merge(reply, success: true)

      if handler = @messageHandlers[message._method]
        try
          handler.apply(this, [ client, message, callback ])
        catch error
          Log.error "Error handling message",
            message: event.data
            error: error.stack
          client.close()
      else
        Log.warn "No handler for #{message._method}"

    client.onclose = (event) =>
      Log.info 'websocket client: disconnected',
        code: event.code,
        reason: event.reason
      index = @clients.indexOf(client)
      @clients.splice(index, 1)

    @send client,
      type:          'header'
      version_name:  Config.getAppVersion()
      version_code:  Config.getAppVersionCode()
      idle_interval: 29000 # FIXME
      push_id:       @pushId
      push_key:      Base64.urlEncode(@pushKey)

    unless @inbandBacklog
      # {"bid":-1,"eid":-1,"type":"oob_include","time":1340156453,"highlight":false,"url":"/chat/oob-loader?key=e82d5ead-bfbd-4a55-94c8-c145798a3520"}
      @send client,
        type: 'oob_include'
        url:  '/chat/backlog'
    else
      @sendBacklog(client)

  send: (client, message, cb) ->
    message = @prepareMessage(message)
    json = JSON.stringify(message)
    Log.silly 'CLIENT SEND:', json
    client.sendQueue.perform (over) =>
      client.send json,
        cb() if cb
        over()
    return message

  prepareMessage: (message) ->
    now = parseInt(Date.now() / 1000)
    message.time      = now   unless message.time
    message.highlight = false unless message.highlight
    message.eid       = -1    unless message.eid
    return message

  addConnection: (options) ->
    new Connection this, options, (conn) =>
      @connections.push conn
      conn.addListener 'event', (event) =>
        @broadcast event
      conn.sendBacklog null, =>
        conn.connect() if conn.autoConnect

  removeConnection: (conn, cb) ->
    conn.delete =>
      @connections.splice(@connections.indexOf(conn), 1)
      @broadcast B.connectionDeleted(conn)
      cb()

  findConnection: (cid) ->
    for conn in @connections
      return conn if conn.id == cid
    return null

  broadcast: (message, cb) ->
    queue = new WorkingQueue(@clients.length + 1)

    Log.silly 'BROADCAST', JSON.stringify(message)
    unless message.is_backlog
      if message.highlight
        queue.perform (over) =>
          @pushClient.sendPush(message, over)

    for client in @clients
      do (client) =>
        queue.perform (over) =>
          @send client, message, over

    queue.whenDone => cb() if cb
    queue.doneAddingJobs()

    return message

  sendBacklog: (client) ->
    @getBacklog (event) =>
      @send client, event

  getBacklog: (callback, done) ->
    queue = new WorkingQueue(1)

    for conn in @connections
      do (conn) =>
        queue.perform (over) =>
          conn.getBacklog ((event) ->
            callback event
          ), over

    queue.whenDone =>
      callback
        type: 'backlog_complete'
      done() if done

    queue.doneAddingJobs()

  messageHandlers:
    heartbeat: (client, message, callback) ->
      @selectedBid = message.selectedBuffer

      seenEids = JSON.parse(message.seenEids)

      queue = new WorkingQueue(1)

      for cid, buffers of seenEids
        connection = @findConnection(parseInt(cid))
        throw "connection not found: #{cid}" unless connection
        for bid, eid of buffers
          buffer = connection.findBuffer(parseInt(bid))
          throw "buffer not found: #{bid}" unless buffer
          do (buffer, eid) =>
            queue.perform (over) =>
              buffer.setLastSeenEid(eid, over)

      queue.whenDone =>
        @db.getAllLastSeenEids (updatedSeenEids) =>
          @send client,
            type: 'heartbeat_echo',
            seenEids: updatedSeenEids

      queue.doneAddingJobs()

    say: (client, message, callback) ->
      conn = @findConnection(message.cid)
      to   = message.to
      text = message.msg

      if text
        # selfMessage event will take care of opening the buffer.
        conn.say(to, text)
        return

      # No message, so just open the buffer.
      conn.getOrCreateBuffer to, 'conversation', (buffer, created) ->
        callback
          name: to
          cid:  conn.id
          type: 'open_buffer'
          _reqid: message._reqid

    join: (client, message, callback) ->
      chan = message.channel
      conn = @findConnection(message.cid)

      conn.join(chan)

      callback
        name: chan
        cid:  conn.id
        type: 'open_buffer'

    part: (client, message, callback) ->
      conn = @findConnection(message.cid)
      conn.part(message.channel)
      callback()

    disconnect: (client, message, callback) ->
      @findConnection(message.cid).disconnect ->
        callback()

    reconnect: (client, message, callback) ->
      @findConnection(message.cid).reconnect =>
        callback()

    'add-server': (client, message, callback) ->
      @db.insertConnection message, (info) =>
        @addConnection info
        callback()

    'edit-server': (client, message, callback) ->
      conn = @findConnection(message.cid)
      conn.edit(message, callback)

    'delete-connection': (client, message, callback) ->
      conn = @findConnection(message.cid)
      @removeConnection(conn, callback)

    'archive-buffer': (client, message, callback) ->
      conn = @findConnection(message.cid)
      buffer = conn.findBuffer(message.id)
      buffer.archive(callback)

    'unarchive-buffer': (client, message, callback) ->
      conn = @findConnection(message.cid)
      buffer = conn.findBuffer(message.id)
      buffer.unarchive(callback)

    'delete-buffer': (client, message, callback) ->
      conn = @findConnection(message.cid)
      buffer = conn.findBuffer(message.id)
      buffer.delete(callback)

    'accept-cert': (client, message, callback) ->
      conn = @findConnection(message.cid)
      conn.acceptCert(message.fingerprint, message.accept, callback)

module.exports = Engine
