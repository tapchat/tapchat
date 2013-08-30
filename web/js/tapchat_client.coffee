class TapchatClient
  @STATE_DISCONNECTED = 0
  @STATE_CONNECTING   = 1
  @STATE_CONNECTED    = 2
  @STATE_LOADING      = 3
  @STATE_LOADED       = 4

  constructor: () ->
    _.extend @, Backbone.Events

    @connectionState = @STATE_DISCONNECTED
    @reqid = 0
    @responseHandlers = {}
    @connections = new ConnectionList()

  connect: ->
    return unless @connectionState == @STATE_DISCONNECTED
  
    @setConnectionState(@STATE_CONNECTING)

    scheme  = if (window.location.protocol == 'https:') then 'wss' else 'ws'
    address = scheme + "://" + window.location.host + "/chat/stream?inband=true"

    @socket = new WebSocket(address)
    
    @socket.onopen = (evt) =>
      @setConnectionState(@STATE_CONNECTED)

    @socket.onclose = (evt) =>
      @setConnectionState(@STATE_DISCONNECTED)
      @socket = null

      for connection in @connections.models
        connection.clientDisconnected()

    @socket.onmessage = (evt) =>
      # console.log(evt.data)
      @processMessage(JSON.parse(evt.data))

    @socket.onerror = () =>
      @handleError() # FIXME

  disconnect: () ->
    return if @connectionState == @STATE_DISCONNECTED
    @socket.close()

  setConnectionState: (state) ->
    @connectionState = state
    @trigger('connection-state-changed', state)

  addServer: (data, callback) ->
    # FIXME

  post: (message, callback) ->
    message._reqid = ++@reqid
    @responseHandlers[message._reqid] = [message, callback]
    @socket.send JSON.stringify(message)

  send: (message, callback) -> # FIXME: Remove this or the other one.
    @post(message, callback)

  processMessage: (message, oob) ->
    @lastMessageAt = new Date()

    # backbone uses 'cid' internally, so use '_cid' instead.
    message._cid = message.cid
    delete message.cid

    if message._reqid?
      reqid = message._reqid

      if message.msg?
        message = message.msg

      if @responseHandlers[reqid]
        info = @responseHandlers[reqid]
        delete @responseHandlers[reqid]

        if message.cid?
          if connection = @connections.get(message.cid)
            connection.handleResponse(message, info.request)

        if info.callback
          info.callback(message, info.request)

      return

    type = message.type

    if handler = @messageHandlers[type]
      handler.apply(this, [message])

    if message._cid?
      if connection = @connections.get(message._cid)
        connection.processMessage(message)

  selectBuffer: (connectionId, bufferId, selected) ->
    unless connection = @connections.get(connectionId)
      # Shouldn't happen...
      return

    unless buffer = connection.buffers.get(bufferId)
      @selectedBuffer = null
      return

    if selected
      @selectedBuffer = buffer
      buffer.markAllRead()
    else
      if @selectedBuffer == buffer
        @selectedBuffer = null

    connection.client.post
      _method: 'heartbeat'
      seenEids: _.tap({}, (o) =>
        o[connection.id] = _.tap({}, (o) =>
          o[buffer.id] = buffer.lastSeenEid
        )
      )
      selectedBuffer: if @selectedBuffer then @selectedBuffer.id else null

  getState: ->
    @connections.map (connection) ->
      _.tap {}, (o) ->
        o[connection.id] = connection.buffers.map (buffer) ->
          _.tap {}, (o) ->
            o[buffer.id] = buffer.lastSeenEid

  messageHandlers: 
    header: (message) ->
      @setConnectionState(@STATE_LOADING)
      # FIXME @idleInterval = message.idle_interval

    stat_user: (message) ->
      @user = message
      @trigger('user-updated', @user)

    backlog_complete: (message) ->
      for connection in @connections.models
        connection.remove() unless connection.exists
      @setConnectionState(@STATE_LOADED)

    makeserver: (message) ->
      if connection = @connections.get(message._cid)
        connection.reload(message)
      else
        @connections.add(new Connection(this, message))

    connection_deleted: (message) ->
      if connection = @connections.get(message._cid)
        @connections.remove(connection)
        connection.stopListening()
        connection.destroy()

    heartbeat_echo: (message) ->
      for cid, buffers of message.seenEids
        if connection = @connections.get(cid)
          for bid, eid of buffers
            if buffer = connection.buffers.get(bid)
              buffer.markRead(eid)

window.TapchatClient = TapchatClient
