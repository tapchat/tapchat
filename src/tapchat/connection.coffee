#
# connection.coffee
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

Irc          = require('../irc/irc')
EventEmitter = require('events').EventEmitter
WorkingQueue = require('capisce').WorkingQueue
util = require 'util'

_ = require('underscore')

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

Log                = require('./log')
ConsoleBuffer      = require('./console_buffer')
ChannelBuffer      = require('./channel_buffer')
ConversationBuffer = require('./conversation_buffer')
B = require('./message_builder')

class Connection extends EventEmitter
  constructor: (engine, options, callback) ->
    @engine = engine

    @buffers = []

    @queue = new WorkingQueue(1)

    @id   = options.cid
    @name = options.name

    @autoConnect = !!options.auto_connect

    @client = new Irc.Client options.server, options.nick,
      name:        options.name
      server:      options.server
      port:        options.port
      secure:      !!options.is_ssl
      userName:    options.user_name
      realName:    options.real_name
      password:    options.server_pass
      autoConnect: false

    @addEventListeners()

    @engine.db.selectBuffers @id, (buffers) =>
      for bufferInfo in buffers
        buffer = @addBuffer bufferInfo
        @consoleBuffer = buffer if buffer instanceof ConsoleBuffer
      unless @consoleBuffer
        @createBuffer '*', 'console', (buffer) =>
          @consoleBuffer = buffer
          callback(this)
      else
        callback(this)

  connect: ->
    @client.connect()

  disconnect: (cb) ->
    if @client
      @client.disconnect(cb)
    else
      cb() if cb

  reconnect: (callback) ->
    @disconnect =>
      @connect()
      callback() if callback

  delete: (cb) ->
    @disconnect =>
      buffer.removeAllListeners() for buffer in @buffers
      @client.removeAllListeners()
      @client = null
      @engine.db.deleteConnection @id, =>
        cb() if cb

  setNick: (nick) ->
    @client.send("NICK #{nick}")

  say: (to, text) ->
    @client.say(to, text)

  join: (chan) ->
    @client.join(chan)

  part: (chan) ->
    @client.part(chan)

  addBuffer: (bufferInfo) =>
    if bufferInfo.type == 'console'
      buffer = new ConsoleBuffer(this, bufferInfo)
    else if bufferInfo.type == 'channel'
      buffer = new ChannelBuffer(this, bufferInfo)
    else if bufferInfo.type == 'conversation'
      buffer = new ConversationBuffer(this, bufferInfo)
    else
      throw "Unknown buffer type: #{bufferInfo.type}"
    @buffers.push(buffer)
    buffer.on 'event', (event) =>
      @emit('event', event)

    @emit 'event', B.makeBuffer(buffer)

    buffer

  removeBuffer: (buffer) ->
    buffer.removeAllListeners()
    @buffers.splice(@buffers.indexOf(buffer), 1)
    @emit 'event', B.deleteBuffer(buffer)

  sendBacklog: (client, callback) ->
    queue = new WorkingQueue(1)

    send = (message) =>
      queue.perform (over) =>
        if client
          @engine.send(client, message, over)
        else
          @engine.broadcast(message, over)

    @getBacklog ((event) =>
      # HACK: end_of_backlog not needed for a new connection (being broadcast to everyone)
      if (event.type != 'end_of_backlog' || (event.type == 'end_of_backlog' and !client))
        send event
      ), ->
        queue.whenDone callback
        queue.doneAddingJobs()

  getBacklog: (callback, done) ->
    callback B.makeServer(this)

    queue = new WorkingQueue(1)
    for buffer in @buffers
      do (buffer) =>
        queue.perform (bufferOver) =>
          callback B.makeBuffer(buffer)

          if buffer instanceof ChannelBuffer and buffer.isJoined
            callback B.channelInit(buffer)

          buffer.getBacklog (events) =>
            callback(event) for event in events
            bufferOver()

    queue.whenDone =>
      callback
        type: 'end_of_backlog'
        cid:  @id

      # FIXME: This is an awful hack. It should really be included in the 'make_server' message.
      if @isConnecting()
        send(merge(B.connecting(this), bid: buffer.id)) for buffer in @buffers

    queue.whenDone done
    queue.doneAddingJobs()

  edit: (options, callback) ->
    @engine.db.updateConnection @id, options, (row) =>
      @updateAttributes(row)
      @engine.broadcast(B.serverDetailsChanged(this))
      callback(row)

  updateAttributes: (options) ->
    serverChanged = (@getHostName() && (@getHostName() != options.server || @getPort() != options.port)) || (@isSSL() != (!!options.ssl)) || (@getServerPass() != options.server_pass)
    nickChanged   = (@getNick()     && (@getNick()     != options.nick))

    @name = options.name

    @client.opt.server   = options.server
    @client.opt.port     = options.port
    @client.opt.secure   = !!options.is_ssl
    @client.opt.nick     = options.nick
    @client.opt.userName = options.user_name
    @client.opt.realName = options.real_name
    @client.opt.password = options.server_pass

    if serverChanged
      @reconnect() # FIXME: Only if previously connected
    else
      @setNick(@client.opt.nick) if nickChanged

  addEventToAllBuffers: (event, callback) ->
    queue = new WorkingQueue(1)
    queue.whenDone -> callback()
    for buffer in @buffers
      do (buffer) =>
        queue.perform (over) =>
          buffer.addEvent event, over
    queue.doneAddingJobs()

  getName: ->
    @name

  getConfiguredNick: ->
    @client.opt.nick

  getNick: ->
    @client.nick

  getRealName: ->
    @client.opt.realName

  getHostName: ->
    @client.opt.server

  getPort: ->
    @client.opt.port

  isDisconnected: ->
    (@client.conn == null || @client.conn.readyState != 'open')

  isConnecting: ->
    (@client.conn != null && @client.conn.readyState == 'opening')

  isSSL: ->
    @client.opt.secure

  getServerPass: ->
    @client.opt.password

  findBuffer: (bid) ->
    for buffer in @buffers
      return buffer if buffer.id == bid
    return null

  getBuffer: (name) ->
    return null unless name
    for buffer in @buffers
      return buffer if buffer.name.toLowerCase() == name.toLowerCase()
    return null

  getOrCreateBuffer: (name, type, callback) ->
    throw 'missing name' unless name
    throw 'missing type' unless type

    buffer = @getBuffer(name)
    return callback(buffer, false) if buffer

    @createBuffer(name, type, callback)

  createBuffer: (name, type, callback) ->
    self = this
    @engine.db.insertBuffer @id, name, type, (bufferInfo) =>
      buffer = self.addBuffer bufferInfo
      callback(buffer, true)

  addEventListeners: ->
    for signalName, signalHandler of @signalHandlers
      do (signalName, signalHandler) =>
        @client.addListener signalName, (args...) =>
          handler = =>
            whitelist = [ 'connecting', 'close', 'abort', 'netError', 'error', 'recvLine' ]
            if @isDisconnected() && (!_.include(whitelist, signalName))
              Log.warn 'Disconnected before event handler ran!',
                connId:   @id,
                connName: @name,
                signal:   signalName
              return _.last(arguments)()
            #Log.silly "Starting event handler for: #{signalName}"
            signalHandler.apply(this, arguments)

          @queue.perform (over) ->
            overWrapper = =>
              #Log.silly "Done with event handler for: #{signalName}"
              over()
            args.push(overWrapper)
            handler args...

  shouldHighlight: (message) ->
    !!message.match(@getNick())

  signalHandlers:
    connecting: (over) ->
      @addEventToAllBuffers B.connecting(this), over

    connect: (over) ->
      @addEventToAllBuffers
        type:     'connected'
        ssl:      @isSSL()
        hostname: @getHostName()
        port:     @getPort(),
        over

    close: (over) ->
      buffer.setJoined(false) for buffer in @buffers when buffer instanceof ChannelBuffer
      @addEventToAllBuffers
        type: 'socket_closed',
        over

    abort: (retryCount, over) ->
      @addEventToAllBuffers
        type:     'connecting_failed'
        hostname: @getHostName()
        port:     @getPort(),
        over

    registered: (message, over) ->
      @addEventToAllBuffers
        type: 'connecting_finished',
        over

      for buffer in @buffers
        # FIXME: Just use isArchived to indicate if should autojoin and remove that column
        @client.join(buffer.name) if buffer instanceof ChannelBuffer && (!buffer.isArchived) && buffer.autoJoin

    motd: (motd, over) ->
      @consoleBuffer.addEvent B.serverMotd(this, motd),
        over

    names: (channel, nicks, over) ->
      if buffer = @getBuffer(channel)
        buffer.setMembers(_.keys(nicks))
        @emit 'event', B.channelInit(buffer)
        over()

    topic: (channel, topic, nick, message, over) ->
      if buffer = @getBuffer(channel)
        buffer.topicText = topic
        buffer.topicBy   = nick
        buffer.topicTime = null
        unless _.isEmpty(nick)
          buffer.addEvent
            type: 'channel_topic'
            author: nick
            topic: topic,
            over
          return
      over()

    join: (channel, nick, message, over) ->
      return @signalHandlers.selfJoin.apply(this, [ channel, message, over ] ) if nick == @getNick()

      if buffer = @getBuffer(channel)
        buffer.addMember(nick)
        buffer.addEvent
          type: 'joined_channel'
          nick: nick,
          over
      else
        over()

    selfJoin: (channel, message, over) ->
      @getOrCreateBuffer channel, 'channel', (buffer) =>
        buffer.addMember(@getNick())
        buffer.setJoined(true)
        buffer.addEvent
          type: 'you_joined_channel',
          over

    part: (channel, nick, reason, message, over) ->
      return @signalHandlers.selfPart.apply(this, [ channel, reason, over ] ) if nick == @getNick()

      if buffer = @getBuffer(channel)
        buffer.removeMember(nick)
        buffer.addEvent
          type: 'parted_channel'
          nick: nick,
          over
      else
        over()

    selfPart: (channel, reason, over) ->
      if buffer = @getBuffer(channel)
        buffer.setJoined(false)
        buffer.addEvent
          type: 'you_parted_channel',
          over
      else
        over()

    kick: (channel, nick, byNick, reason, message, over) ->
      if buffer = @getBuffer(channel)
        buffer.removeMember(nick)
        buffer.addEvent
          type: 'kicked_channel'
          nick: nick
          kicker: byNick
          msg: reason,
          over
      else
        over()

    selfQuit: (reason, over) ->
      buffer.setJoined(false) for buffer in @buffers when buffer.type instanceof ChannelBuffer
      @addEventToAllBuffers
        type: 'quit_server'
        msg:  reason,
        over

    quit: (nick, reason, channels, message, over) ->
      queue = new WorkingQueue(1)

      for name in [ nick ].concat(channels)
        do (name) =>
          queue.perform (bufferOver) =>
            if buffer = @getBuffer(name)
              buffer.removeMember(nick) if buffer instanceof ChannelBuffer
              buffer.addEvent
                type: 'quit'
                nick: nick
                msg:  reason, ->
                  bufferOver()
            else
              bufferOver()

      queue.whenDone -> over()
      queue.doneAddingJobs()

    kill: (nick, reason, channels, message, over) ->
      for name in [ nick ].concat(channels)
        if buffer = @getBuffer(name)
          buffer.removeMember(nick)
          buffer.addEvent
            type:   'kill'
            from:   nick,
            reason: message,
            over
        else
          over()

    selfMessage: (to, text, over) ->
      if to.match(/^[&#]/)
        if buffer = @getBuffer(to)
          buffer.addEvent
            type:      'buffer_msg'
            from:      @getNick()
            chan:      to
            msg:       text
            highlight: false
            self:      true,
            over
        else
          over()
      else
        @getOrCreateBuffer to, 'conversation', (buffer) =>
          buffer.unarchive =>
            buffer.addEvent
              type:      'buffer_msg'
              from:      @getNick()
              msg:       text
              highlight: false
              self:      true,
              over

    message: (nick, to, text, message, over) ->
      if to.match(/^[&#]/)
        if buffer = @getBuffer(to)
          highlight = @shouldHighlight(text)
          buffer.addEvent
            type:      'buffer_msg'
            from:      nick
            chan:      to
            msg:       text
            highlight: highlight,
            self:      false,
            over
        else
          over()
      else
        bufferName = if nick == @getNick() then to else nick
        @getOrCreateBuffer bufferName, 'conversation', (buffer) =>
          buffer.unarchive =>
            buffer.addEvent
              type:      'buffer_msg'
              from:      nick
              msg:       text
              highlight: true
              self:      false,
              over

    action: (from, to, text, over) ->
      isChannel = to.match(/^[&#]/)
      bufferName = if isChannel then to else from
      buffer = @getBuffer(bufferName)
      if buffer
        buffer.addEvent
          type: 'buffer_me_msg'
          from: from
          msg:  text,
          over
      else
        over()

    notice: (nick, to, text, message, over) ->
      buffer = if (!nick || !to) then @consoleBuffer else @getBuffer(to)
      if buffer
        buffer.addEvent
          type: 'notice'
          msg:  text,
          over
      else
        over()

    nick: (oldnick, newnick, channels, message, over) ->
      queue = new WorkingQueue(1)

      # FIXME: @getBuffer(oldnick)?.setName(newnick)

      for name in [ oldnick ].concat(channels)
        if buffer = @getBuffer(name)
          queue.perform (addEventOver) =>
            buffer.addEvent
              type: 'nickchange'
              newnick: newnick
              oldnick: oldnick,
              addEventOver

      queue.whenDone -> over()
      queue.doneAddingJobs()

    selfNick: (oldnick, newnick, channels, message, over) ->
      queue = new WorkingQueue(1)

      # FIXME: @getBuffer(oldnick)?.setName(newnick)

      queue.perform (addEventOver) =>
        @consoleBuffer.addEvent
          type: 'you_nickchange'
          newnick: newnick
          oldnick: oldnick,
          addEventOver

      for name in [ oldnick ].concat(channels)
        if buffer = @getBuffer(name)
          queue.perform (addEventOver) =>
            buffer.addEvent
              type: 'you_nickchange'
              newnick: newnick
              oldnick: oldnick,
              addEventOver

      queue.whenDone -> over()
      queue.doneAddingJobs()

    invite: (channel, from, message, over) ->
      @consoleBuffer.addEvent
        type:    'channel_invite'
        channel: channel
        from:    from,
        over

    sendLine: (message, over) ->
      Log.silly "IRC SEND [#{@getName()}]: #{message}"
      over()

    recvLine: (message, over) ->
      Log.silly "IRC RECV [#{@getName()}]: #{message}"
      over()

    netError: (error, over) ->
      Log.error "Net error [#{@getName()}]: #{error} #{error.stack}"
      @consoleBuffer.addEvent
        type: 'error'
        msg: error,
        =>
          @disconnect()
          over()

    error: (error, over) ->
      Log.error "Error [#{@getName()}]: #{error.stack}"
      @consoleBuffer.addEvent
        type: 'error',
        msg: error.args.join(' '), =>
          @disconnect()
          over()

module.exports = Connection
