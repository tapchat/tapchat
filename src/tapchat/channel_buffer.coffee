#
# channel_buffer.coffee
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

ChatBuffer = require('./chat_buffer')

class ChannelMember
  constructor: (nick, mode) ->
    @nick = nick
    @mode = mode || ''

  addMode: (mode) ->
    @mode += mode unless @mode.indexOf(mode) >= 0

  delMode: (mode) ->
    @mode = @mode.replace(mode, '')

class ChannelBuffer extends ChatBuffer
  type: 'channel'
  members: {}

  constructor: (connection, info) ->
    super(connection, info)
    @autoJoin = info.auto_join

  setJoined: (joined, callback) ->
    @unarchive =>
      @connection.engine.db.setBufferAutoJoin @connection.id, @id, joined, =>
        @isJoined = joined
        @autoJoin = joined
        @members = {} unless joined
        callback()

  setMembers: (nicks) ->
    @members = {}

    for nick,mode of nicks
      @addMember(nick, mode)

  addMember: (nick, mode) ->
    @members[nick] = new ChannelMember(nick, mode)

  renameMember: (oldNick, newNick) ->
    member = @members[oldNick]
    delete @members[oldNick]

    member.nick = newNick
    @members[newNick] = member

  removeMember: (nick) ->
    delete @members[nick]

  getMember: (nick) ->
    @members[nick]

  archive: (callback) ->
    return callback() if this instanceof ChannelBuffer and @isJoined
    super(callback)

module.exports = ChannelBuffer