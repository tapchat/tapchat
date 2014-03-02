#
# backlog_db.coffee
#
# Copyright (C) 2012-2013 Eric Butler <eric@codebutler.com>
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

Path     = require('path')
Fs       = require('fs')
Squel    = require('squel')
Sqlite3  = require('sqlite3').verbose()
UUID     = require('node-uuid')
Crypto   = require('crypto')
_        = require('underscore')

Config     = require('./config')
DBMigrator = require('./db_migrator')

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

SCHEMA_VERSION = 5

class BacklogDB
  constructor: (callback) ->
    @file = Path.join(Config.getDataDirectory(), 'backlog.db')

    migrationsDir = __dirname + '../../../db'

    @db = new Sqlite3.Database @file, =>
      m = new DBMigrator
        db:  @db
        dir: migrationsDir
      m.migrate SCHEMA_VERSION, =>
        callback(this)

  close: ->
    @db.close()

  selectUsers: (callback) ->
    @db.all 'SELECT * FROM users', (err, rows) ->
      throw err if err
      callback(rows)

  selectUser: (id, callback) ->
    @db.get 'SELECT * FROM users WHERE uid = $uid',
      $uid: id,
      (err, row) ->
        throw err if err
        callback(row)

  selectUserByName: (name, callback) ->
    @db.get 'SELECT * FROM users WHERE name = $name',
      $name: name,
      (err, row) ->
        throw err if err
        callback(row)

  selectConnections: (uid, callback) ->
    @db.all 'SELECT * FROM connections WHERE uid = $uid',
      $uid: uid,
      (err, rows) ->
        throw err if err
        callback(rows)

  selectConnection: (cid, callback) ->
    @db.get 'SELECT * FROM connections WHERE cid = $cid',
      $cid: cid,
      (err, row) ->
        throw err if err
        callback(row)

  selectBuffers: (cid, callback) ->
    @db.all 'SELECT * FROM buffers WHERE cid = $cid',
      $cid: cid,
      (err, rows) ->
        throw err if err
        callback(rows)

  insertUser: (name, password_hash, is_admin, callback) ->
    throw 'name is required' if _.isEmpty(name)
    throw 'password hash is required' if _.isEmpty(password_hash)

    push_id  = UUID.v4()
    push_key = Crypto.randomBytes(32).toString('base64')

    self = this
    @db.run """
      INSERT INTO users (name, password, is_admin, push_id, push_key)
      VALUES ($name, $password, $is_admin, $push_id, $push_key)
      """,
      $name:     name
      $password: password_hash
      $is_admin: is_admin
      $push_id:  push_id
      $push_key: push_key,
      (err) ->
        throw err if err
        self.selectUser @lastID, (row) ->
          callback(row)

  insertConnection: (uid, options, callback) ->
    throw 'hostname is required' if _.isEmpty(options.hostname)
    throw 'port is required'     unless parseInt(options.port) > 0
    throw 'nickname is required' if _.isEmpty(options.nickname)
    throw 'realname is required' if _.isEmpty(options.realname)
    self = this
    @db.run """
      INSERT INTO connections (uid, name, server, port, is_ssl, nick, user_name, real_name, server_pass)
      VALUES ($uid, $name, $server, $port, $is_ssl, $nick, $user_name, $real_name, $server_pass)
      """,
      $uid:         uid,
      $name:        options.name ? options.hostname
      $server:      options.hostname
      $port:        options.port
      $nick:        options.nickname
      $user_name:   options.nickname # FIXME
      $real_name:   options.realname
      $server_pass: options.server_pass
      $is_ssl:      options.ssl || false,
      (err) ->
        throw err if err
        self.selectConnection @lastID, (row) ->
          callback(row)

  updateUser: (uid, options, callback) ->
    self = this

    sql = Squel.update().table('users')
    sql.where('uid = $uid')

    setAttribute = (name, options, key) =>
      sql.set name, options[key] if _.has(options, key)

    setAttribute 'password', options, 'password_hash'
    setAttribute 'is_admin', options, 'is_admin'

    @db.run sql.toString(),
      $uid: uid,
      (err) ->
        throw err if err
        self.selectUser uid, (row) ->
          callback(row)

  updateConnection: (cid, options, callback) ->
    self = this

    sql = Squel.update().table('connections')
    sql.where('cid = $cid')

    setAttribute = (name, value) =>
      sql.set name, value if value && value != undefined

    name = unless _.isEmpty(options.name) then options.name else options.hostname

    setAttribute 'name',        name
    setAttribute 'server',      options.hostname
    setAttribute 'port',        options.port
    setAttribute 'nick',        options.nickname
    setAttribute 'user_name',   options.nickname # FIXME
    setAttribute 'real_name',   options.realname

    setAttribute 'ssl_fingerprint', options.ssl_fingerprint

    if _.has(options, 'ssl')
      # options.ssl might be a string or a number
      isSSL = if (!!Number(options.ssl)) then 1 else 0
      sql.set 'is_ssl', isSSL

    setAttribute 'server_pass', options.server_pass

    @db.run sql.toString(),
      $cid: cid,
      (err) ->
        throw err if err
        self.selectConnection cid, (row) ->
          callback(row)

  deleteConnection: (cid, callback) ->
    params =
      $cid: cid

    @db.serialize =>
      @db.run 'BEGIN TRANSACTION'
      @db.run 'DELETE FROM events      WHERE bid IN (SELECT bid FROM buffers WHERE cid = $cid)', params
      @db.run 'DELETE FROM buffers     WHERE cid = $cid', params
      @db.run 'DELETE FROM connections WHERE cid = $cid', params
      @db.run 'COMMIT', (err) =>
        throw err if err
        callback()

  insertBuffer: (cid, uid, name, type, callback) ->
    autoJoin = (type == 'channel')
    @db.run 'INSERT INTO buffers (cid, uid, name, type, auto_join) VALUES ($cid, $uid, $name, $type, $auto_join)',
      $cid:       cid
      $uid:       uid
      $name:      name
      $type:      type
      $auto_join: autoJoin,
      (err) ->
        throw err if err
        callback
          cid:  cid
          bid:  @lastID
          name: name
          type: type

  deleteBuffer: (cid, bid, callback) ->
    @db.serialize =>
      @db.run 'BEGIN TRANSACTION'
      @db.run 'DELETE FROM events WHERE bid = $bid',
        $bid: bid
      @db.run 'DELETE FROM buffers WHERE cid = $cid AND bid = $bid',
        $cid: cid
        $bid: bid
      @db.run 'COMMIT', (err) =>
        throw err if err
        callback()

  deleteUser: (uid, callback) ->
    @db.run 'DELETE FROM users WHERE uid = $uid',
      $uid: uid,
      (err) =>
        throw err if err
        callback()

  insertEvent: (event, callback) ->
    query = """
      INSERT INTO events (bid, data)
      VALUES ($bid, $data)
    """
    @db.run query,
      $bid:  event.bid
      $data: JSON.stringify(event),
      (err) ->
        throw err if err
        callback merge({ eid: @lastID }, event)

  selectEvents: (bid, callback) ->
    query = """
      SELECT eid, bid, data, created_at
      FROM events
      WHERE eid IN (
          SELECT eid
          FROM EVENTS
          WHERE bid = $bid
          ORDER BY eid DESC
          LIMIT $limit
      )
      ORDER BY eid ASC
    """
    @db.all query,
      $bid:   bid
      $limit: 50, # FIXME
      (err, rows) ->
        throw err if err
        callback(rows)

  selectEventsRange: (cid, bid, num, beforeid, callback) ->
    # FIXME: cid not used
    query = """
      SELECT eid, bid, data, created_at
      FROM events
      WHERE eid IN (
          SELECT eid
          FROM EVENTS
          WHERE
            bid = $bid AND
            eid < $beforeid
          ORDER BY eid DESC
          LIMIT $limit
      )
      ORDER BY eid ASC
    """
    @db.all query,
      $bid:      bid
      $beforeid: beforeid
      $limit:    num,
      (err, rows) ->
        throw err if err
        callback(rows)

  getAllLastSeenEids: (uid, callback) ->
    query = """
      SELECT cid, bid, last_seen_eid
      FROM buffers
      WHERE uid = $uid AND
      last_seen_eid IS NOT NULL
    """

    @db.all query,
      $uid: uid,
      (err, rows) ->
        throw err if err

        result = {}

        for row in rows
          cid = parseInt(row.cid)
          bid = parseInt(row.bid)
          eid = parseInt(row.last_seen_eid)
          result[cid] ?= {}
          result[cid][bid] = eid

        callback(result)

  setBufferLastSeenEid: (cid, bid, eid, callback) ->
    query = """
      UPDATE buffers
      SET last_seen_eid = $eid,
      updated_at = $time
      WHERE cid = $cid AND bid = $bid
    """

    @db.run query,
      $eid: eid
      $cid: cid
      $bid: bid
      $time: new Date().getTime(),
      (err) ->
        throw err if err
        callback()

  setBufferArchived: (cid, bid, archived, callback) ->
    query = """
      UPDATE buffers
      SET archived = $archived,
      updated_at = $time
      WHERE cid = $cid AND bid = $bid
    """

    @db.run query,
      $cid: cid
      $bid: bid
      $archived: (if archived then 1 else 0)
      $time: new Date().getTime(),
      (err) ->
        throw err if err
        callback()

  setBufferAutoJoin: (cid, bid, autoJoin, callback) ->
    query = """
      UPDATE buffers
      SET auto_join = $auto_join,
      updated_at = $time
      WHERE cid = $cid AND bid = $bid
    """

    @db.run query,
      $cid: cid,
      $bid: bid,
      $auto_join: autoJoin,
      $time: new Date().getTime(),
      (err) ->
        throw err if err
        callback()

module.exports = BacklogDB
