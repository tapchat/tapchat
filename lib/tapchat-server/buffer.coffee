EventEmitter = require('events').EventEmitter

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

B = require('./message_builder')

class Buffer extends EventEmitter
  TYPE_CONSOLE = 'console'
  TYPE_CHANNEL = 'channel'
  TYPE_QUERY   = 'conversation'

  members: []

  constructor: (connection, id, name) ->
    @connection = connection
    @id         = id
    @name       = name    

    if name == '*'
      @type = TYPE_CONSOLE
    else if name.match(/^[&#]/)
      @type = TYPE_CHANNEL
    else
      @type = TYPE_QUERY

    @events = [] # FIXME: Read from database!

  addEvent: (event) ->
    event = merge(event,
      cid: @connection.id
      bid: @id
      eid: (@events.length + 1))
    
    # FIXME: Write to database!
    @events.push event

    @emit 'event', event

  setMembers: (nicks) ->
    @members.clear
    @addMember(nick) for nick in nicks

  addMember: (nick) ->
    @members.push
      nick: nick
      realName: '' # FIXME
      host: '' # FIXME

  renameMember: (oldNick, newNick) ->
    @removeMember(oldNick)
    @addMember(newNick)

  removeMember: (nick) ->
    # FIXME


module.exports = Buffer
