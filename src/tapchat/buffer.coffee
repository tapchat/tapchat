EventEmitter = require('events').EventEmitter

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

B = require('./message_builder')
_ = require('underscore')

class Buffer extends EventEmitter
  constructor: (connection, info) ->
    @connection = connection
    @id         = info.bid
    @name       = info.name
    @type       = info.type
    @autoJoin   = info.auto_join

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
    event.cid = @connection.id
    event.bid = @id

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
