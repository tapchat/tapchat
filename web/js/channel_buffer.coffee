class Member extends Backbone.Model
  constructor: (@buffer, attrs) ->
    super(attrs)
    
class ChannelBuffer extends Buffer
  constructor: (connection, attrs) ->
    super(connection, attrs)
    @members = new MemberList()

  join: ->
    @connection.part(@get('name'))

  part: ->
    @connection.join(@get('name'))

  isActive: ->
    super and @get('joined')

  reload: (attrs) ->
    super
    @set('joined', attrs.joined)

  messageHandlers:
    channel_init: (message) ->
      if message.topic?
        @set('topic', message.topic)
      for memberAttrs in message.members
        @members.add(new Member(this, memberAttrs))
      @set('joined', true)

  initializedMessageHandlers:
    channel_topic: (message) ->
      @set('topic', message.topic)

    joined_channel: (message) ->
      @members.add(new Member(this, message))

    parted_channel: (message) ->
      @members.removeByNick(message.nick)

    quit: (message) ->
      if message.nick?
        @members.removeByNick(message.nick)

    kicked_channel: (message) ->
      @members.removeByNick(message.nick)

    you_joined_channel: (message) ->
      @set('joined', true)

    you_parted_channel: (message) ->
      @set('joined', false)

    nickchange: (message) ->
      @members.updateNick(message)

    you_nickchange: (message) ->
      @members.updateNick(message)

window.ChannelBuffer = ChannelBuffer