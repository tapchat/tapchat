class ConversationBuffer extends Buffer
  constructor: (connection, attrs) ->
    super(connection, attrs)

window.ConversationBuffer = ConversationBuffer