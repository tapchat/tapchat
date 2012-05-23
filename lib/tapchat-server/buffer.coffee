EventEmitter = require('events').EventEmitter

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

B = require('./message_builder')
_ = require('underscore')

EXCLUDED_FROM_BACKLOG = [
  'makeserver', 'makebuffer', 'connection_deleted', 'delete_buffer', 'channel_init'
]

class Buffer extends EventEmitter
  constructor: (connection, info) ->
    @connection = connection
    @id         = info.bid
    @name       = info.name
    @type       = info.type

    @members = {}

    throw 'buffer: missing connection' unless @connection
    throw 'buffer: missing id'         unless @id
    throw 'buffer: missing name'       unless @name
    throw 'buffer: missing type'       unless @type

  getBacklog: (callback) ->
    @connection.engine.db.selectEvents @id, (rows) ->
      rows = ((merge
        is_backlog: true,
        eid:        row.eid,
        time:       row.created_at,
        JSON.parse(row.data)) for row in rows)
      callback(rows)

  addEvent: (event, callback) ->
    event = merge(event,
      cid: @connection.id
      bid: @id)

    if _.contains(EXCLUDED_FROM_BACKLOG, event.type)
      event = merge(event, eid: -1)
      @emit 'event', event
      callback(event) if callback

    else
      @connection.engine.db.insertEvent event, (event) =>
        # event will have an eid now
        @emit 'event', event
        callback(event) if callback

  setMembers: (nicks) ->
    @members = {}
    @addMember(nick) for nick in nicks

  addMember: (nick) ->
    @members[nick] =
      nick:     nick
      realName: '' # FIXME
      host:     '' # FIXME

  renameMember: (oldNick, newNick) ->
    @removeMember(oldNick)
    @addMember(newNick)

  removeMember: (nick) ->
    delete @members[nick]

  setJoined: (joined) ->
    console.log 'set joined', @name, joined
    @isJoined = joined
    @members = {} unless joined

  # FIXME: setName: (name) ->
  # @connection.engine.db.updateBuffer { name: name } @id, =>
  #   @name = name

# FIXME: Better way to handle consts in coffeescript?
Buffer.prototype.TYPE_CONSOLE = 'console'
Buffer.prototype.TYPE_CHANNEL = 'channel'
Buffer.prototype.TYPE_QUERY   = 'conversation'

module.exports = Buffer
