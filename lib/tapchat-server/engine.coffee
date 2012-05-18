WebSocketServer = require('ws').Server
CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

Util = require 'util'

B = require('./message_builder')
Connection = require './connection'

class Engine
  connections: []
  clients: []
  
  constructor: (port) ->
    @server = new WebSocketServer
      port: port
    @server.on 'connection', (client) =>
      @addClient(client)

  addClient: (client) ->
    console.log 'got client'

    @clients.push(client)

    client.on 'message', (message) =>
      console.log "Got message: #{message}"
      message = JSON.parse(message)
      handler = @messageHandlers[message._method]
      if handler
        handler.apply(this, [ client, message ])
      else
        console.log "No handler for #{message._method}"

    @sendHeader(client)
    @sendBacklog(client)

  send: (client, message) ->
    message = @prepareMessage(message)
    message.eid = -1 unless message.eid
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
    conn = new Connection(this, options)

    conn.addListener 'event', (event) =>
      @broadcast event

    @connections.push conn

    @broadcast B.makeServer(conn)
    for buffer in conn.buffers
      @broadcast B.makeBuffer(buffer)
      # No need to send backlog here. It's either a new connection
      # or we're starting up and no clients have connected yet.

  removeConnection: (name) ->
    throw 'Not Implemented' # FIXME

    conn = @findConnection(name)
    @engine.broadcast B.connectionDeleted(conn)

  findConnection: (cid) ->
    for conn in @connections
      return conn if conn.id == cid
    return null

  start: ->
    conn.connect() for conn in @connections

  broadcast: (message) ->
    console.log 'BROADCAST: ' + JSON.stringify(message)

    message.eid = -1 unless message.eid # FIXME

    message = @prepareMessage(message)
    json    = JSON.stringify(message)
    for client in @clients
      client.send json

    return message

  sendBacklog: (client) ->
    for conn in @connections
      @send client, B.makeServer(conn)
  
      for buffer in conn.buffers
        @send client, B.makeBuffer(buffer) 
        for event in buffer.events
          @send client, event
      
      @send client,
        type: 'end_of_backlog'
        cid:  conn.id
      @send client,
        type: 'backlog_complete'

  messageHandlers:
    # FIXME 
    # heartbeat: (client, messaage) ->
    
    say: (client, message) ->
      conn = @findConnection(message.cid)
      to   = message.to
      text = message.msg

      is_channel = to.match(/^[&#]/)

      bufferExists = !!conn.getBuffer(to)

      # Create buffer only if not a channel.
      buffer = conn.getBuffer(to, !is_channel)

      conn.say(to, text)

      if (!bufferExists) && buffer
        # Tell client to wait for and show the new buffer
        return {
          name: to
          cid:  conn.id
          type: 'open_buffer'
        }

    join: (client, message) ->
      chan = message.channel
      conn = @findConnection(message.cid)

      conn.join(chan)

      return {
        name: chan
        cid:  conn.id
        type: 'open_buffer'
      }

    # FIXME
    #part:

    # FIXME
    #'hide-buffer':

module.exports = Engine
