#
# message_builder.coffee
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

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers
_ = require('underscore')

module.exports =
  makeServer: (conn) ->
    type:         'makeserver'
    cid:          conn.id
    name:         conn.getName()
    nick:         conn.getConfiguredNick()
    realname:     conn.getRealName()
    hostname:     conn.getHostName()
    port:         conn.getPort()
    disconnected: conn.isDisconnected()
    ssl:          conn.isSSL()
    server_pass:  conn.getServerPass()

  serverDetailsChanged: (conn) ->
    merge(@makeServer(conn), type: 'server_details_changed')

  connecting: (conn) ->
    cid:      conn.id
    type:     'connecting'
    nick:     conn.getConfiguredNick(),
    ssl:      conn.isSSL()
    hostname: conn.getHostName()
    port:     conn.getPort(),

  makeBuffer: (buffer) ->
    cid: buffer.connection.id
    bid: buffer.id
    msg =
      type:        'makebuffer'
      buffer_type: buffer.type
      cid:         buffer.connection.id
      bid:         buffer.id
      name:        buffer.name
      archived:    buffer.isArchived

    msg.last_seen_eid = buffer.lastSeenEid if buffer.lastSeenEid
    msg.joined = buffer.isJoined if buffer.type == 'channel'
    return msg

  channelInit: (buffer) ->
    type:   'channel_init'
    cid:    buffer.connection.id
    bid:    buffer.id
    joined: buffer.isJoined
    chan:   buffer.name
    mode:   buffer.mode
    topic:
      topic_text:   buffer.topicText
      topic_time:   buffer.topicTime
      topic_author: buffer.topicBy
    members: _.values(buffer.members).map (member) ->
      nick:     member.nick
      realname: member.realName
      usermask: member.host

  deleteBuffer: (buffer) ->
    type: 'delete_buffer'
    cid:  buffer.connection.id
    bid:  buffer.id

  quit: (buffer, nick, reason) ->
    type:     'quit'
    cid:      buffer.connection.id
    bid:      buffer.id
    nick:     nick
    msg:      reason
    hostmask: null # FIXME

  serverMotd: (conn, motd) ->
    throw 'no conn' unless conn
    throw 'no console buffer' unless conn.consoleBuffer

    type: 'server_motd'
    cid:  conn.id
    bid:  conn.consoleBuffer.id
    msg:  motd

  connectionDeleted: (conn) ->
    type: 'connection_deleted'
    cid: conn.id
