WorkingQueue = require('capisce').WorkingQueue

WebSocketServer = require('ws').Server
CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

Util = require 'util'

B = require('./message_builder')
Buffer = require('./buffer')
Connection = require './connection'
BacklogDB = require './backlog_db'

class Engine
  constructor: (backlog_file, port) ->
    @connections = []
    @clients     = []
  
    @db = new BacklogDB backlog_file, =>
      @server = new WebSocketServer
        port: port
      @server.on 'connection', (client) =>
        @addClient(client)

      @db.selectConnections (conns) =>
        @addConnection connInfo for connInfo in conns

  addClient: (client) ->
    console.log 'got client'

    @clients.push(client)

    client.on 'message', (message) =>
      console.log "Got message: #{message}"
      message = JSON.parse(message)

      callback = (reply) =>
        @send client,
          _reqid: message._reqid
          msg:    merge(reply, success: true)

      if handler = @messageHandlers[message._method]
        handler.apply(this, [ client, message, callback ]) 
      else
        console.log "No handler for #{message._method}"

    client.on 'close', (code, message) =>
      console.log 'client disconnected', code, message
      index = @clients.indexOf(client)
      @clients.splice(index, 1)

    @sendHeader(client)
    @sendBacklog(client)

  send: (client, message) ->
    message = @prepareMessage(message)
    message.eid = -1 unless message.eid
    console.log 'CLIENT SEND:', JSON.stringify(message)
    client.send JSON.stringify(message)
    return message

  prepareMessage: (message) ->
    message.time      = Date.now() unless message.time
    message.highlight = false      unless message.highlight
    return message

  sendHeader: (client) ->
    @send client,
      type: 'header'
      idle_interval: 29000 # FIXME

  addConnection: (options) ->
    new Connection this, options, (conn) =>
      conn.addListener 'event', (event) =>
        @broadcast event

      @connections.push conn

      @broadcast B.makeServer(conn)
      for buffer in conn.buffers
        buffer.addEvent B.makeBuffer(buffer)
        # No need to send backlog here. It's either a new connection
        # or we're starting up and no clients have connected yet.

      conn.connect() if conn.autoConnect

  removeConnection: (name) ->
    throw 'Not Implemented' # FIXME
    # conn = @findConnection(name)
    # @engine.broadcast B.connectionDeleted(conn)

  findConnection: (cid) ->
    for conn in @connections
      return conn if conn.id == cid
    return null

  broadcast: (message) ->
    message = @prepareMessage(message)
    json    = JSON.stringify(message)
    for client in @clients
      client.send json

    return message

  sendBacklog: (client) ->
    queue = new WorkingQueue(1)

    for conn in @connections
      do (conn) =>
        queue.perform (over) ->
          conn.sendBacklog client, ->
            over()

    queue.whenDone =>
      @send client,
        type: 'backlog_complete'

    queue.doneAddingJobs()

  makeServer: (conn) ->
    type:         'makeserver'
    cid:          conn.id
    name:         conn.name
    nick:         conn.getNick()
    realname:     conn.getRealName()
    hostname:     conn.getHostName()
    port:         conn.getPort()
    disconnected: conn.isDisconnected()
    ssl:          conn.isSSL()

  makeBuffer: (buffer) ->
    msg =
      type:        'makebuffer'
      buffer_type: buffer.type
      cid:         buffer.connection.id
      bid:         buffer.id
      name:        buffer.name
    msg.joined = buffer.isJoined if buffer.type == 'channel'
    return msg

  messageHandlers:
    # FIXME 
    # heartbeat: (client, messaage, callback) ->
    
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
      @findConnection(message.cid).disconnect()
      callback()

    'add-server': (client, message, callback) ->
      @db.insertConnection message, (info) =>
        @addConnection info
        callback()

    'edit-server': (client, message, callback) ->
      conn = @findConnection(message.cid)
      conn.edit message, (attrs) =>
        callback()
        @send client, B.serverDetailsChanged(conn)

module.exports = Engine
