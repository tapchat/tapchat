class ConsoleBuffer extends Buffer
  constructor: (connection, attrs) ->
    super(connection, attrs)
    
window.ConsoleBuffer = ConsoleBuffer