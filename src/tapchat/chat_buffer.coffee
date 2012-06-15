#
# chat_buffer.coffee
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

Buffer = require('./buffer')

class ChatBuffer extends Buffer
  constructor: (connection, info) ->
    super(connection, info)
    @isArchived  = !!info.archived

  archive: (callback) ->
    return callback() if @isArchived
    @connection.engine.db.setBufferArchived @connection.id, @id, true,  =>
      @isArchived = true
      @connection.engine.broadcast
        type: 'buffer_archived'
        cid:  @connection.id
        bid:  @id,
        callback

  unarchive: (callback) ->
    return callback() unless @isArchived
    @connection.engine.db.setBufferArchived @connection.id, @id, false, =>
      @isArchived = false
      @connection.engine.broadcast
        type: 'buffer_unarchived'
        cid:  @connection.id
        bid:  @id,
        callback

  delete: (callback) ->
    return callback() if @isJoined
    @connection.engine.db.deleteBuffer @connection.id, @id, =>
      @connection.removeBuffer(this, callback)

module.exports = ChatBuffer