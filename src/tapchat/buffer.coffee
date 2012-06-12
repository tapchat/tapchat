#
# buffer.coffee
#
# Copyright (C) 2012 Eric Butler <eric@codebutler.com>
#
# This file is part of TapChat.
#
# TapChat is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# TapChat is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with TapChat.  If not, see <http://www.gnu.org/licenses/>.

EventEmitter = require('events').EventEmitter

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

B = require('./message_builder')
_ = require('underscore')

class Buffer extends EventEmitter
  constructor: (connection, info) ->
    @connection  = connection
    @id          = info.bid
    @name        = info.name
    @type        = info.type
    @autoJoin    = info.auto_join
    @lastSeenEid = info.last_seen_eid

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
