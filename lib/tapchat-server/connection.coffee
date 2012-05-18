EventEmitter = require('events').EventEmitter
Irc          = require 'irc'
util = require 'util'

_ = require('underscore')

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

Buffer = require('./buffer')
B = require('./message_builder')

class Connection extends EventEmitter
  buffers: [] # {}

  constructor: (engine, options) ->
    @engine = engine

    @id     = del options, 'id'
    @name   = del options, 'name'
    @server = del options, 'server'

    nick = del options, 'nick'

    options.autoConnect = false
    options.debug       = true

    @client = new Irc.Client @server, nick, options

    # FIXME: Read backlog database... restore all buffers...

    @addBuffer new Buffer(this, 0, '*')
    
    for signalName, signalHandler of @signalHandlers
      do (signalName, signalHandler) =>
        @client.addListener signalName, (args...) =>
          signalHandler.apply(this, arguments)

  connect: ->
    console.log 'connect!'
    @client.connect()

  say: (to, text) ->
    @client.say(to, text)

  join: (chan) ->
    @client.join(chan)

  addBuffer: (buffer) =>
    buffer.on 'event', (event) =>
      @emit('event', event)
    @buffers.push(buffer)
    @emit 'event', B.makeBuffer(buffer)
    buffer

  removeBuffer: (buffer) ->
    @buffers.remove(buffer)
    @emit B.deleteBuffer(buffer)

  addEventToAllBuffers: (event) ->
    buffer.addEvent(event) for buffer in @buffers

  getNick: ->
    @client.nick

  getRealName: ->
    @client.opt.realName

  getHostName: ->
    @client.opt.server

  getPort: ->
    @client.opt.port

  isDisconnected: ->
    false # FIXME

  isSSL: ->
    @client.opt.secure

  getBuffer: (name, create = false) ->
    for buffer in @buffers
      return buffer if buffer.name == name

    if create
      id = @buffers.length + 1 # FIXME
      return @addBuffer(new Buffer(this, id, name))

    return null

  getConsoleBuffer: ->
    for buffer in @buffers
      return buffer if buffer.name == '*'

  signalHandlers:
    connecting: -> # FIXME: Doesn't exist
      @addEventToAllBuffers
        type:     'connecting'
        hostname: @getHostName()
        port:     @getPort()
        ssl:      @isSSL()
        nick:     @getNick()

    # FIXME: irc.js doesn't emit events when reconnecting
     
    abort: (retryCount) -> # FIXME: Wrong event. needs to be for every failed attempt.
      @addEventToAllBuffers
        type: 'connecting_failed'
        hostname: @sever
        port: @port

    # FIXME: Pipe this through from the socket...
    close: ->
      @addEventToAllBuffers
        type: 'socket_closed'

    # FIXME: Pipe this through from the socket...
    connect: ->
      @addEventToAllBuffers
        type: 'connected'
        ssl:  @isSSL()

    netError: (ex) ->

    registered: (message) ->
      @addEventToAllBuffers
        type: 'connecting_finished'

    motd: (motd) ->
      @getConsoleBuffer().addEvent B.serverMotd(this, motd)

    names: (channel, nicks) ->
      buffer = @getBuffer(channel)
      if buffer
        buffer.setMembers(_.keys(nicks))
        buffer.addEvent B.channelInit(buffer) # FIXME: Don't add this as an event.

    topic: (channel, topic, nick, message) ->
      @getBuffer(channel)?.addEvent
        type: 'channel_topic'
        author: nick
        topic: topic

    join: (channel, nick, message) ->
      shouldCreate = (nick == @getNick())
      buffer = @getBuffer(channel, shouldCreate)

      return unless buffer

      buffer.addMember(nick)

      if nick == @getNick()
        buffer.addEvent
          type: 'you_joined_channel'
      else
        buffer.addEvent
          type: 'joined_channel'
          nick: nick

    part: (channel, nick, reason, message) ->
      buffer = @getBuffer(channel)
      buffer?.removeMember(nick)
      buffer?.addEvent
        type: 'parted_channel'
        nick: nick

    kick: (channel, nick, byNick, reason, message) ->
      buffer = @getBuffer(channel)
      buffer?.removeMember(nick)
      buffer?.addEvent
        type: 'kicked_channel'
        nick: nick
        kicker: byNick
        msg: reason

    # FIXME: Does not exist!
    self_quit: (reason, message) ->
      @addEventToAllBuffers
        type: 'quit_server'
        msg:  reason

    quit: (nick, reason, channels, message) ->
      for name in [ nick ].concat(channels)
        buffer = @getBuffer(name)
        buffer?.removeMember(nick)
        buffer?.addEvent
          type: 'quit'
          nick: nick
          msg:  reason

    kill: (nick, reason, channels, message) ->
      for name in [ nick ].concat(channels)
        buffer = @getBuffer(name)
        buffer?.removeMember(nick)
        # FIXME add the event

    selfMessage: (to, text) ->
      if to.match(/^[&#]/)
        @getBuffer(to)?.addEvent
          type: 'buffer_msg'
          from: @getNick()
          chan: to
          msg: text
          highlight: false # FIXME
          self: false # FIXME
      else
        @getBuffer(to, true)?.addEvent
          type:      'buffer_msg'
          from:      @getNick()
          msg:       text
          highlight: false
          self:      false

    message: (nick, to, text, message) ->
      if to.match(/^[&#]/)
        @getBuffer(to)?.addEvent
          type: 'buffer_msg'
          from: nick
          chan: to
          msg: text
          highlight: false # FIXME
          self: false # FIXME
      else
        @getBuffer(nick, true)?.addEvent
          type:      'buffer_msg'
          from:      nick
          msg:       text
          highlight: true
          self:      false

    action: (from, to, text) ->
      isChannel = to.match(/^[&#]/)
      bufferName = if isChannel then to else from
      @getBuffer(bufferName)?.addEvent
        type: 'buffer_me_msg'
        from:  from
        msg: text

    notice: (nick, to, text, message) ->
      buffer = if (to == null) then @getConsoleBuffer() else @getBuffer(to)
      buffer?.addEvent
        type: 'notice'
        msg:  text

    nick: (oldnick, newnick, channels, message) ->
      for name in [ nick ].concat(channels)
        @getBuffer(name)?.addEvent
          type: 'nickchange'
          newnick: newnick
          oldnick: oldnick

    invite: (channel, from, message) ->
      @getConsoleBuffer()?.emit
        type:    'channel_invite'
        channel: channel
        from:    from

    raw: (message) ->
      console.log "RAW: #{@name} #{JSON.stringify(message)}"

    error: (error) ->
      console.log "ERR: #{JSON.stringify(error)}" # FIXME

module.exports = Connection
