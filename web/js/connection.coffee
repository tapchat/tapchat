class Connection extends Backbone.Model
  @STATUS_DISCONNECTED = 'disconnected'
  @STATUS_CONNECTING   = 'connecting'
  @STATUS_CONNECTED    = 'connected'

  idAttribute: '_cid'

  constructor: (@client, attrs) ->
    super(attrs) # FIXME: Whitelist attrs
    @buffers = new BufferList()
    @updateDetails(attrs)

  clientDisconnected: ->
    @exists = false
    for buffer in @buffers.models
      buffer.clientDisconnected()

  join: (channelName, callback) ->
    if channel = @buffers.findByName(channelName)
      if channel.get('joined')
        @trigger('open-buffer', channel)
        callback() if callback
        return

    @post
      _method: 'join'
      channel: channelName,
      callback

  part: (channelName, callback) ->
    @post
      _method: 'part'
      channel: channelName,
      callback

  say: (to, text, callback) ->
    @post
      _method: 'say'
      to: to
      msg: text,
      callback

  deleteConnection: (callback) ->
    @post
      _method: 'delete-connection'
      cid:     @id,
      callback

  post: (message, callback) ->
    message.cid = @id
    @client.post message, callback

  openBuffer: (nick) ->
    if buffer = @buffers.findByName(nick)
      buffer.unarchive()
      @trigger('open-buffer', buffer) # FIXME
    else
      @say(nick, null, null)

  reconnect: (callback) ->
    @send
      _method: 'reconnect',
      callback

  disconnect: (callback) ->
    @send
      _method: 'disconnect',
      callback

  delete: (callback) ->
    @send
      _method: 'delete-connection',
      callback

  edit: (data, callback) ->
    data._method = 'edit-server'
    @send data, callback

  reload: (message) ->
    @updateDetails(message)

  send: (message, callback) ->
    message.cid = @id
    @client.send message, callback

  processMessage: (message) ->
    type = message.type

    if (!message.is_backlog) and (!@isBacklog)
      if handler = @initializedMessageHandlers[type]
        handler.apply(this, [message])

    if handler = @messageHandlers[type]
      handler.apply(this, [message])

    if message.bid?
      if buffer = @buffers.get(message.bid)
        buffer.processMessage(message)

  handleResponse: (response, request) ->
    type = response.type
    if type == 'open_buffer'
      if buffer = @buffers.findByName(response.name)
        @trigger('open-buffer', buffer)
        @pendingOpenBufferName = null
      else
        @pendingOpenBufferName = response.name

  updateDetails: (message) ->
    @exists = true
    @isBacklog = (@client.connectionState != TapchatClient.STATE_LOADED)
    for name in ['name', 'nick', 'realname', 'hostname', 'port', 'ssl', 'server_pass']
      @set(name, message[name])

    if message.disconnected
      @set('status', Connection.STATUS_DISCONNECTED)
    else
      @set('status', Connection.STATUS_CONNECTED)

  messageHandlers:
    end_of_backlog: (message) ->
      @isBacklog = false
      for buffer in @buffers.models
        @removeBuffer(buffer) unless buffer.exists

    makebuffer: (message) ->
      message.id = message._cid
      if buffer = @buffers.get(message.bid)
        buffer.reload(message)
        return
      switch message.buffer_type
        when 'channel'
          buffer = new ChannelBuffer(this, message)
        when 'conversation'
          buffer = new ConversationBuffer(this, message)
        when 'console'
          buffer = new ConsoleBuffer(this, message)
          @consoleBuffer = buffer
        else
          throw "Unknown buffer type #{message.buffer_type}"
      buffer.connection = this
      @buffers.add(buffer)

      if @pendingOpenBufferName? and @pendingOpenBufferName == buffer.get('name')
        @trigger('open-buffer', buffer)
        @pendingOpenBufferName = null

  initializedMessageHandlers:
    #status_changed: (message) ->
    #  @set('status', message.new_status)
    #  if message.new_status == Connection.STATUS_CONNECTING
    #    @set('nick', message.nick)

    connecting: (message) ->
      @set('nick', message.nick)
      @set('status', Connection.STATUS_CONNECTING)

    connecting_retry: (message) ->
      @set('status', Connection.STATUS_CONNECTING)

    waiting_to_retry: (message) ->
      @set('status', Connection.STATUS_CONNECTING)

    connecting_cancelled: (message) ->
      @set('status', Connection.STATUS_DISCONNECTED)

    connecting_failed: (message) ->
      @set('status', Connection.STATUS_DISCONNECTED)

    connecting_finished: (message) ->
      @set('status', Connection.STATUS_CONNECTED)

    socket_closed: (message) ->
      @set('status', Connection.STATUS_DISCONNECTED)

    delete_buffer: (message) ->
      if buffer = @buffers.get(message.bid)
        @buffers.remove(buffer)
        buffer.stopListening()
        buffer.destroy()

    buffer_archived: (message) ->
      if buffer = @buffers.get(message.bid)
        buffer.set('archived', true)

    buffer_unarchived: (message) ->
      if buffer = @buffers.get(message.bid)
        buffer.set('archived', false)

    server_details_changed: (message) ->
      @set(message) # FIXME: Whitelist attrs.

    you_nickchange: (message) ->
      @set('nick', message.newnick)

    invalid_cert: (message) ->
      @trigger('invalid-cert', message)

window.Connection = Connection