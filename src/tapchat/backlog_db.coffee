#
# backlog_db.coffee
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

Path    = require 'path'
Fs      = require 'fs'
Squel   = require 'squel'
Sqlite3 = require('sqlite3').verbose()
_       = require('underscore')

Config = require './config'

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class BacklogDB
  constructor: (engine, callback) ->
    @file = Path.join(Config.getDataDirectory(), 'backlog.db')

    @db = new Sqlite3.Database @file, =>
      @createTables callback

  createTables: (callback) =>
    # FIXME: Add some sort of migrations system in here
    statements = [
      """
      CREATE TABLE IF NOT EXISTS connections (
          cid          INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
          name         TEXT     NOT NULL,
          server       TEXT     NOT NULL,
          port         INTEGER  NOT NULL,
          is_ssl       BOOLEAN  NOT NULL,
          nick         TEXT     NOT NULL,
          user_name    TEXT     NOT NULL,
          real_name    TEXT     NOT NULL,
          auto_connect BOOLEAN  NOT NULL DEFAULT 1,
          created_at   DATETIME DEFAULT (strftime('%s','now')),
          updated_at   DATETIME
      );
      """
      """
      CREATE TABLE IF NOT EXISTS buffers (
          bid           INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
          cid           INTEGER  NOT NULL,
          name          TEXT     NOT NULL,
          type          TEXT     NOT NULL,
          archived      BOOLEAN  NOT NULL DEFAULT 0,
          auto_join     BOOLEAN,
          last_seen_eid INTEGER,
          created_at    DATETIME DEFAULT (strftime('%s','now')),
          updated_at    DATETIME
      );
      """
      """
      CREATE TABLE IF NOT EXISTS events (
          eid        INTEGER  NOT NULL PRIMARY KEY AUTOINCREMENT,
          bid        INTEGER  NOT NULL,
          data       TEXT     NOT NULL,
          created_at DATETIME DEFAULT (strftime('%s','now'))
      );
      """
      """
      CREATE INDEX IF NOT EXISTS connections_name ON connections (name);
      """
      """
      CREATE INDEX IF NOT EXISTS events_bid ON events (bid);
      """
    ]

    @db.serialize =>
      count = statements.length
      for sql in statements
        @db.run sql, (err) ->
          count--
          throw err if err
          callback() if count == 0

  selectConnections: (callback) ->
    @db.all 'SELECT * FROM connections', (err, rows) ->
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

  insertConnection: (options, callback) ->
    throw 'hostname is required' if _.isEmpty(options.hostname)
    throw 'port is required'     unless parseInt(options.port) > 0
    throw 'nickname is required' if _.isEmpty(options.nickname)
    throw 'realname is required' if _.isEmpty(options.realname)
    self = this
    @db.run """
      INSERT INTO connections (name, server, port, is_ssl, nick, user_name, real_name)
      VALUES ($name, $server, $port, $is_ssl, $nick, $user_name, $real_name)
      """,
      $name:      options.hostname # FIXME
      $server:    options.hostname
      $port:      options.port
      $nick:      options.nickname
      $user_name: options.nickname # FIXME
      $real_name: options.realname
      $is_ssl:    options.ssl || false,
      (err) ->
        throw err if err
        self.selectConnection @lastID, (row) ->
          callback(row)

  updateConnection: (cid, options, callback) ->
    self = this

    sql = Squel.update().table('connections')
    sql.where('cid = $cid')

    setAttribute = (name, value) =>
      sql.set name, value if value

    setAttribute 'name',      options.hostname # FIXME
    setAttribute 'server',    options.hostname
    setAttribute 'port',      options.port
    setAttribute 'nick',      options.nickname
    setAttribute 'user_name', options.nickname # FIXME
    setAttribute 'real_name', options.realname

    isSSL = if options.ssl then 1 else 0
    sql.set 'is_ssl', isSSL

    @db.run sql.toString(),
      $cid: cid,
      (err) ->
        throw err if err
        self.selectConnection cid, (row) ->
          callback(row)

  deleteConnection: (cid, callback) ->
    @db.run "DELETE FROM connections WHERE cid = $cid", $cid: cid, (err) ->
      throw err if err
      throw "Didn't find connection" unless @changes
      callback()

  insertBuffer: (cid, name, type, callback) ->
    autoJoin = (type == 'channel')
    @db.run 'INSERT INTO buffers (cid, name, type, auto_join) VALUES ($cid, $name, $type, $auto_join)',
      $cid:       cid
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

  getAllLastSeenEids: (callback) ->
    query = """
      SELECT cid, bid, last_seen_eid FROM buffers WHERE last_seen_eid IS NOT NULL
    """

    @db.all query,
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

  setBufferLastSeenEid: (bid, eid, callback) ->
    query = """
      UPDATE buffers
      SET last_seen_eid = $eid,
      updated_at = $time
      WHERE bid = $bid
    """

    @db.run query,
      $eid: eid
      $bid: bid
      $time: new Date().getTime(),
      (err) ->
        throw err if err
        callback()

module.exports = BacklogDB
