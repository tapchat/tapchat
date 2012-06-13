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

Path         = require('path')
Fs           = require('fs')
WorkingQueue = require('capisce').WorkingQueue
Http         = require('http')
Express      = require('express')
Url          = require('url')
WebSocket    = require('faye-websocket')
PasswordHash = require('password-hash')
CoffeeScript = require('coffee-script')
Util         = require('util')
Daemon       = require('daemon')
_            = require 'underscore'

Config     = require './config'
B          = require './message_builder'
Buffer     = require './buffer'
Connection = require './connection'
BacklogDB  = require './backlog_db'

{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class Engine
  constructor: (config, callback) ->
    @connections = []
    @clients     = []

    @password = config.password
    @port     = config.port

    throw 'No password set!' unless PasswordHash.isHashed(@password)

    @db = new BacklogDB this, =>
      @startServer(@port, callback)

      @db.selectConnections (conns) =>
        @addConnection connInfo for connInfo in conns

  daemonize: ->
    logfile = Config.getLogFile()
    pidfile = Config.getPidFile()

    @pid = Daemon.daemonize(logfile, pidfile)
    console.log('Daemon started successfully with pid:', @pid);

  startServer: (port, callback) ->
    @app = Express.createServer
      key:  Fs.readFileSync(Config.getCertFile())
      cert: Fs.readFileSync(Config.getCertFile())

    @app.use(Express.static(__dirname + '/../../web'))

    @app.set 'views', __dirname + '/../../web'
    @app.set 'view engine', 'html.eco'
    @app.register('.html.eco', require('eco'))
    @app.get '/', (req, res) =>
      res.render 'index',
        layout:          false,
        num_clients:     @clients.length
        num_connections: @connections.length

    @app.addListener 'upgrade', (request, socket, head) =>
      query = Url.parse(request.url, true).query
      unless PasswordHash.verify(query.password, @password)
        # FIXME: Return proper HTTP error
        console.log 'bad password'
        request.socket.end('foo')
        return

      ws = new WebSocket(request, socket, head)
      console.log 'websocket client: connected'
      @addClient(ws)

    @app.listen port, =>
      console.log "\nTapChat ready at https://localhost:#{port}\n"
      callback(this) if callback

  addClient: (client) ->
    client.sendQueue = new WorkingQueue(1)
    @clients.push(client)

    client.onmessage = (event) =>
      message = JSON.parse(event.data)

      unless message._reqid
        console.log 'Missing _reqid, ignoring message', event.data
        return

      console.log 'Got message:', event.data

      callback = (reply) =>
        @send client,
          _reqid: message._reqid
          msg:    merge(reply, success: true)

      if handler = @messageHandlers[message._method]
        try
          handler.apply(this, [ client, message, callback ])
        catch error
          console.log "Error handling message", error, event.data, error.stack
          client.close()
      else
        console.log "No handler for #{message._method}"

    client.onclose = (event) =>
      console.log 'websocket client: disconnected', event.code, event.reason
      index = @clients.indexOf(client)
      @clients.splice(index, 1)

    @sendBacklog(client)

  send: (client, message, cb) ->
    message = @prepareMessage(message)
    #console.log 'CLIENT SEND:', JSON.stringify(message)
    client.sendQueue.perform (over) =>
      client.send JSON.stringify(message),
        cb() if cb
        over()
    return message

  prepareMessage: (message) ->
    message.time      = Date.now() unless message.time
    message.highlight = false      unless message.highlight
    message.eid       = -1         unless message.eid
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
    queue = new WorkingQueue(@clients.length)

    #console.log 'BROADCAST', JSON.stringify(message)

    for client in @clients
      do (client) =>
        queue.perform (over) =>
          @send client, message, over

    queue.whenDone => cb() if cb
    queue.doneAddingJobs()

    return message

  sendBacklog: (client) ->
    queue = new WorkingQueue(1)

    queue.perform (over) =>
      @send client,
        type: 'header'
        version: Config.getAppVersion(),
        idle_interval: 29000, # FIXME
        over

    for conn in @connections
      do (conn) =>
        queue.perform (over) =>
          conn.sendBacklog client, over

    queue.whenDone =>
      @send client,
        type: 'backlog_complete'

    queue.doneAddingJobs()

  messageHandlers:
    heartbeat: (client, message, callback) ->
      @selectedBid = message.selectedBuffer

      seenEids = JSON.parse(message.seenEids)

      queue = new WorkingQueue(1)

      for cid, buffers of seenEids
        for bid, eid of buffers
          do (bid, eid) =>
            queue.perform (over) =>
              @db.setBufferLastSeenEid(bid, eid, over)

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
      conn.getOrCreateBuffer to, Buffer::TYPE_QUERY, (buffer, created) ->
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

module.exports = Engine
