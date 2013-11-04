#
# user.coffee
#
# Copyright (C) 2013 Eric Butler <eric@codebutler.com>
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

WorkingQueue = require('capisce').WorkingQueue

Log        = require('./log')
Config     = require './config'
Base64     = require '../base64'
B          = require './message_builder'
Buffer     = require './buffer'
DataBuffer = require('buffer').Buffer
Connection = require './connection'
PushClient = require './push_client'

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class User
  constructor: (engine, info) ->
    @connections = []
    @clients     = []

    @engine = engine

    @id         = info.uid
    @name       = info.name
    @is_admin   = !!info.is_admin
    @pushId     = info.push_id
    @pushKey    = new DataBuffer(info.push_key, 'base64')
    @pushClient = new PushClient(this)

    @engine.db.selectConnections @id, (conns) =>
      @addConnection connInfo for connInfo in conns

  edit: (options, callback) ->
    @engine.db.updateUser @id, options, (row) =>
      @updateAttributes(row)
      callback(row)

  updateAttributes: (options) ->
    @is_admin = !!options.is_admin

  asJson: ->
    id: @id
    name: @name
    is_admin: @is_admin

  addClient: (client, inbandBacklog) ->
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
            error: error
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

    @send client,
      type: 'stat_user'
      id: @id
      name: @name
      is_admin: @is_admin
      num_active_connections: 0 # FIXME

    unless inbandBacklog
      # {"bid":-1,"eid":-1,"type":"oob_include","time":1340156453,"highlight":false,"url":"/chat/oob-loader?key=e82d5ead-bfbd-4a55-94c8-c145798a3520"}
      @send client,
        type: 'oob_include'
        url:  '/chat/backlog'
    else
      @sendBacklog(client)

  removeClient: (client) ->
    client.close()
    @clients.splice(@clients.indexOf(client), 1)

  send: (client, message, cb) ->
    message = @prepareMessage(message)
    json = JSON.stringify(message)
    Log.silly 'CLIENT SEND:', json
    client.sendQueue.perform (over) =>
      client.send json,
        cb() if cb
        over()
    return message

  isBufferSelected: (bid) ->
    for client in @clients
      return true if client.selectedBid == bid
    return false

  prepareMessage: (message) ->
    now = parseInt(Date.now() / 1000)
    message.time      = now   unless message.time
    message.highlight = false unless message.highlight
    message.eid       = -1    unless message.eid
    return message

  addConnection: (options) ->
    new Connection this, @engine, options, (conn) =>
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
      if message.highlight and message.bid and (!@isBufferSelected(message.bid))
        queue.perform (over) =>
          @pushClient.sendPush(message, over)

    for client in @clients
      do (client) =>
        queue.perform (over) =>
          @send client, message, over

    queue.onceDone cb if cb
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

    queue.onceDone =>
      callback
        type: 'backlog_complete'
      done() if done

    queue.doneAddingJobs()

  delete: (cb) ->
    queue = new WorkingQueue(1)

    @removeClient client for client in @clients

    for conn in @connections
      do (conn) =>
        queue.perform (over) =>
          @removeConnection conn, over

    queue.onceDone =>
      @engine.db.deleteUser @id, =>
        cb() if cb

    queue.doneAddingJobs()

  messageHandlers:
    heartbeat: (client, message, callback) ->
      if message.selectedBuffer?
        client.selectedBid = message.selectedBuffer

      if message.seenEids?
        if typeof message.seenEids == 'string'
          message.seenEids = JSON.parse(message.seenEids)

        seenEids = message.seenEids

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

      queue.onceDone =>
        @engine.db.getAllLastSeenEids @id, (updatedSeenEids) =>
          @broadcast
            type: 'heartbeat_echo',
            seenEids: updatedSeenEids

      queue.doneAddingJobs()

    say: (client, message, callback) ->
      conn = @findConnection(message.cid)
      to   = message.to
      text = message.msg

      # FIXME: Implement commands.
      if to == '*'
        conn.consoleBuffer.addEvent
          type: 'error'
          msg: 'Commands not yet supported.',
          callback
        return

      if text
        if text.indexOf('/me ') == 0
          conn.action(to, text.substring(4))
        else
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
      @engine.db.insertConnection @id, message, (info) =>
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

module.exports = User
