# Somewhat compatible with perl's DBIx::Migration

Path         = require('path')
Fs           = require('fs')
WorkingQueue = require('capisce').WorkingQueue

class DBMigrator
  constructor: (properties) ->
    @db  = properties.db
    @dir = properties.dir

  migrate: (targetVersion, callback) ->
    @ensureMigrationTable =>
      @getCurrentVersion (currentVersion) =>
        @runMigrations(currentVersion, targetVersion, callback)

  runMigrations: (currentVersion, targetVersion, callback) ->
    queue = new WorkingQueue(1)

    if currentVersion >= targetVersion
      callback()
      return

    for version in [currentVersion+1..targetVersion]
      do (version) =>
        queue.perform (over) =>
          @runMigration(version, over)

    queue.whenDone(callback)
    queue.doneAddingJobs()

  runMigration: (version, callback) ->
    console.log 'Running migration', version

    file = Path.join(@dir, "schema_#{version}_up.sql")
    sql  = Fs.readFileSync(file).toString()

    queue = new WorkingQueue(1)

    queue.perform (over) =>
      @db.run "BEGIN TRANSACTION", (err) ->
        throw err if err
        over()

    queue.perform (over) =>
      @db.exec sql, (err) ->
        throw err if err
        over()

    queue.perform (over) =>
      @setCurrentVersion(version, over)

    queue.perform (over) =>
      @db.run "COMMIT", (err) ->
        throw err if err
        over()

    queue.whenDone callback

  ensureMigrationTable: (callback) ->
    sql = """
      CREATE TABLE IF NOT EXISTS dbix_migration (
        name 'CHAR(64)' PRIMARY KEY,
        value 'CHAR(64)'
      );
      INSERT OR IGNORE INTO dbix_migration (name, value) VALUES ('version', 0);
    """

    @db.exec sql, (err) ->
      throw err if err
      callback()

  getCurrentVersion: (callback) ->
    sql = """
      SELECT value FROM dbix_migration WHERE name = 'version';
    """

    @db.get sql, (err, row) =>
      throw err if err
      ver = if row then parseInt(row.value) else 0
      callback(ver)

  setCurrentVersion: (version, callback) ->
    sql = """
      UPDATE dbix_migration SET value = $version WHERE name = 'version'
    """
    @db.run sql,
      $version: version,
      (err) =>
        throw err if err
        callback()

module.exports = DBMigrator