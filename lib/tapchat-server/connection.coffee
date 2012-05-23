EventEmitter = require('events').EventEmitter
Irc          = require 'irc'
WorkingQueue = require('capisce').WorkingQueue
util = require 'util'

_ = require('underscore')

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

Buffer = require('./buffer')
B = require('./message_builder')

class Connection extends EventEmitter
  constructor: (engine, options, callback) ->
    @engine = engine

    @queue = new WorkingQueue(1)

    @id          = options.cid
    @name        = options.name
    @server      = options.server
    @port        = options.port
    @secure      = !!options.is_ssl
    @autoConnect = options.auto_connect
    @nick        = options.nick
    @userName    = options.user_name
    @realName    = options.real_name

    @buffers = []

    @client = new Irc.Client @server, @nick,
      server:      @server
      port:        @port
      secure:      @secure
      nick:        @nick
      userName:    @userName
      realName:    @realName
      autoConnect: false
      debug:       true

    for signalName, signalHandler of @signalHandlers
      do (signalName, signalHandler) =>
        @client.addListener signalName, (args...) =>
          handler = =>
            signalHandler.apply(this, arguments)
          @queue.perform handler, arguments...

    @engine.db.getBuffers @id, (buffers) =>
      for bufferInfo in buffers
        buffer = @addBuffer bufferInfo
        @consoleBuffer = buffer if buffer.type == 'console'
      unless @consoleBuffer
        @createBuffer '*', 'console', (buffer) =>
          @consoleBuffer = buffer
          callback(this)
      else
        callback(this)

  connect: ->
    @client.connect()

  disconnect: ->
    @client.disconnect()

  say: (to, text) ->
    @client.say(to, text)

  join: (chan) ->
    @client.join(chan)

  part: (chan) ->
    @client.part(chan)

  addBuffer: (bufferInfo) =>
    buffer = new Buffer(this, bufferInfo)
    @buffers.push(buffer)
    buffer.on 'event', (event) =>
      @emit('event', event)
    buffer.addEvent B.makeBuffer(buffer)

    buffer

  removeBuffer: (buffer) ->
    @buffers.remove(buffer)
    @emit B.deleteBuffer(buffer)

  sendBacklog: (client, callback) ->
    queue = new WorkingQueue(1)

    @engine.send client, B.makeServer(this)

    for buffer in @buffers
      do (buffer) =>
        queue.perform (over) =>
          buffer.addEvent B.makeBuffer(buffer), over

        if buffer.type == 'channel' and buffer.isJoined
          queue.perform (over) =>
            buffer.addEvent B.channelInit(buffer), over

        queue.perform (over) =>
          buffer.getBacklog (events) =>
            @engine.send client, event for event in events
            over()

    queue.whenDone =>
      @engine.send client,
        type: 'end_of_backlog'
        cid:  @id
      callback()

    queue.doneAddingJobs()

  addEventToAllBuffers: (event, callback) ->
    queue = new WorkingQueue(1)
    queue.whenDone -> callback()
    for buffer in @buffers
      do (buffer) =>
        queue.perform (over) =>
          buffer.addEvent event, =>
            over()
    queue.doneAddingJobs()

  getNick: ->
    @client.nick || @nick

  getRealName: ->
    @client.opt.realName

  getHostName: ->
    @client.opt.server

  getPort: ->
    @client.opt.port

  isDisconnected: ->
    !@client.connected

  isSSL: ->
    @client.opt.secure

  getBuffer: (name) ->
    for buffer in @buffers
      throw "WTF!! CID: #{@id} CNAME: #{@name} BID: #{buffer.id} BNAME: #{buffer.name} BCID: #{buffer.connection.id}" unless (buffer.connection.id == @id)
      return buffer if buffer.name == name
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

  signalHandlers:
    connecting: (over) ->
      @addEventToAllBuffers
        type:     'connecting'
        nick:     @getNick(),
        ssl:      @isSSL()
        hostname: @server
        port:     @port,
        over

    connect: (over) ->
      @addEventToAllBuffers
        type:     'connected'
        ssl:      @isSSL()
        hostname: @server
        port:     @port,
        over

    close: (over) ->
      buffer.setJoined(false) for buffer in @buffers when buffer.type == 'channel'
      @addEventToAllBuffers
        type: 'socket_closed',
        over
     
    abort: (retryCount, over) ->
      @addEventToAllBuffers
        type:     'connecting_failed'
        hostname: @sever
        port:     @port,
        over

    netError: (ex, over) ->
      over()

    registered: (message, over) ->
      @addEventToAllBuffers
        type: 'connecting_finished',
        over

    motd: (motd, over) ->
      @consoleBuffer.addEvent B.serverMotd(this, motd),
        over

    names: (channel, nicks, over) ->
      if buffer = @getBuffer(channel)
        buffer.setMembers(_.keys(nicks))
        buffer.addEvent B.channelInit(buffer), over

    topic: (channel, topic, nick, message, over) ->
      if buffer = @getBuffer(channel)
        buffer.addEvent
          type: 'channel_topic'
          author: nick
          topic: topic,
          over
      else
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
      @getOrCreateBuffer channel, Buffer::TYPE_CHANNEL, (buffer) =>
        buffer.addMember(@getNick())
        buffer.setJoined(true)
        buffer.addEvent
          type: 'you_joined_channel',
          over

    part: (channel, nick, reason, message, over) ->
      return @signalHandlers.selfPart.apply(this, [ channel, reason, over ] ) if nick == @getNick()

      if buffer = @getBuffer(channel)
        buffer.removeMember(nick)
        buffer.isJoined = false
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
      buffer.setJoined(false) for buffer in @buffers when buffer.type == 'channel'
      @addEventToAllBuffers
        type: 'quit_server'
        msg:  reason,
        over

    quit: (nick, reason, channels, message, over) ->
      queue = new WorkerQueue(1)

      for name in [ nick ].concat(channels)
        queue.perform do (name, bufferOver) =>
          if buffer = @getBuffer(name)
            buffer.removeMember(nick)
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
            reason: message, ->
              over()
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
            highlight: false # FIXME
            self:      true,
            over
        else
          over()
      else
        @getOrCreateBuffer to, Buffer::TYPE_QUERY, (buffer) =>
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
          buffer.addEvent
            type:      'buffer_msg'
            from:      nick
            chan:      to
            msg:       text
            highlight: false # FIXME
            self:      false,
            over
        else
          over()
      else
        @getOrCreateBuffer nick, Buffer::TYPE_QUERY, (buffer) =>
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
      for name in [ oldnick ].concat(channels)
        if buffer = @getBuffer(name)
          # FIXME: buffer.setName(newnick)
          buffer.addEvent
            type: 'nickchange'
            newnick: newnick
            oldnick: oldnick,
            over
        else
          over()

    invite: (channel, from, message, over) ->
      @getConsoleBuffer.addEvent
        type:    'channel_invite'
        channel: channel
        from:    from,
      over()

    raw: (message, over) ->
      console.log "RAW: #{@name} #{JSON.stringify(message)}"
      over()

    error: (error, over) ->
      console.log "ERR: #{JSON.stringify(error)}" # FIXME: Some sort of error handling...
      over()

module.exports = Connection
