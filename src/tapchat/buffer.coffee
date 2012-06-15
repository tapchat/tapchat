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
    @lastSeenEid = info.last_seen_eid

    throw 'buffer: missing connection' unless @connection
    throw 'buffer: missing id'         unless @id
    throw 'buffer: missing name'       unless @name

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

  setLastSeenEid: (eid, callback) ->
    @connection.engine.db.setBufferLastSeenEid @connection.id, @id, eid, =>
      @lastSeenEid = eid
      callback()

module.exports = Buffer
