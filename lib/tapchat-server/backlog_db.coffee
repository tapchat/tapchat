Path    = require 'path'
Fs      = require 'fs'
Sqlite3 = require('sqlite3').verbose()

CoffeeScript = require 'coffee-script'
{starts, ends, compact, count, merge, extend, flatten, del, last} = CoffeeScript.helpers

class BacklogDB
  constructor: (file, callback) ->
    @file = file
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

  selectConnections: (connectionCallback) ->
    @db.all 'SELECT * FROM connections', (err, rows) ->
      throw err if err
      connectionCallback(rows)

  getBuffers: (cid, callback) ->
    @db.all 'SELECT * FROM buffers WHERE cid = $cid',
      $cid: cid,
      (err, rows) ->
        throw err if err
        callback(rows)

  insertBuffer: (cid, name, type, callback) ->
    @db.run 'INSERT INTO buffers (cid, name, type) VALUES ($cid, $name, $type)', 
      $cid:  cid
      $name: name
      $type: type,
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
      $limit: 1000, # FIXME
      (err, rows) ->
        throw err if err
        callback(rows)

module.exports = BacklogDB
