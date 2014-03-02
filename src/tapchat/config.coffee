#
# config.coffee
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

Program      = require('commander')
WorkingQueue = require('capisce').WorkingQueue
PasswordHash = require('password-hash')
Path         = require('path')
Fs           = require('fs')
Mkdirp       = require('mkdirp')
ChildProcess = require('child_process')

Config =
  getAppVersion: ->
    JSON.parse(Fs.readFileSync(__dirname + "/../../package.json")).version;

  getAppVersionCode: ->
    JSON.parse(Fs.readFileSync(__dirname + "/../../package.json")).versionCode;

  getDataDirectory: ->
    home = process.env['HOME']
    if process.platform == 'darwin'
      dir = Path.join(home, 'Library', 'Application Support', 'TapChat')
    else
      dir = Path.join(home, '.tapchat')

    Mkdirp.sync(dir)
    return dir

  load: (callback) ->
    Config.readConfig (config) =>
      unless config
        Config.setup(callback)
        return

      if config.password
        Config.migrateOldInitialUser(config, callback)
      else
        callback(config)

  setup: (callback)->
    console.log 'Welcome to TapChat!'

    config = {}

    queue = new WorkingQueue(1)

    queue.perform (over) =>
      Program.prompt 'Choose a port [8067]: ', (port) ->
        config.port = port || 8067
        over()

    initialUser = {}

    queue.perform (over) =>
      Program.prompt 'Choose a username: ', (username) ->
        initialUser.name = username
        over()

    queue.perform (over) =>
      Program.password 'Choose a password:', '*', (password) ->
        initialUser.password = PasswordHash.generate(password)
        over()

    queue.perform (over) =>
      Config.generateCert over

    queue.onceDone =>
      Config.saveConfig config, (config) =>
        @insertUser initialUser, =>
          callback(config)

    queue.doneAddingJobs()

  generateCert: (callback) ->
    certFile = Config.getCertFile()
    Fs.exists certFile, (exists) =>
      unless exists
        console.log '\nGenerating SSL certificate (this may take a minute)...'
        cmd = "openssl req -new -x509 -days 10000 -nodes -out '#{certFile}' -keyout '#{certFile}' -subj '/CN=tapchat'"
        ChildProcess.exec cmd, (error, stdout, stderr) =>
          throw error if error
          Config.getFingerprint (fingerprint) ->
            console.log "Your SSL fingerprint is: #{fingerprint}"
            callback()
      else
        callback()

  getFingerprint: (callback) ->
    cmd = "openssl x509 -fingerprint -noout -in '#{Config.getCertFile()}'"
    ChildProcess.exec cmd, (error, stdout, stderr) =>
      throw error if error
      callback(stdout.replace(/^SHA1 Fingerprint=/, ''))

  readConfig: (callback) ->
    Fs.exists Config.getConfigFile(), (exists) =>
      if exists
        Fs.readFile Config.getConfigFile(), (err, data) =>
          throw err if err
          config = JSON.parse(data)
          callback(config)
      else
        callback(null)

  saveConfig: (config, callback) ->
    Fs.writeFile Config.getConfigFile(), JSON.stringify(config, null, 4), (err) =>
      throw err if err
      callback(config)

  getConfigFile: ->
    Path.join(Config.getDataDirectory(), 'config.json')

  getCertFile: ->
    Path.join(Config.getDataDirectory(), 'tapchat.pem')

  getPidFile: ->
    Path.join(Config.getDataDirectory(), 'tapchat.pid')

  getLogFile: ->
    Path.join(Config.getDataDirectory(), 'tapchat.log')

  migrateOldInitialUser: (config, callback) ->
    # This migrates to the new db-based user system.
    # Can delete this eventually...
    console.log 'Migrating old user to DB...'

    initialUser =
      password: config.password

    delete config.password

    # FIXME: This prompt sometimes causes the app to not exit correctly after daemonizing.
    Program.prompt 'Set your username: ', (username) =>
      initialUser.name = username
      @insertUser initialUser, =>
        Config.saveConfig config, =>
          callback(config)

  insertUser: (user, callback) ->
    BacklogDB = require('./backlog_db')
    new BacklogDB (db) ->
      db.insertUser user.name, user.password, true, ->
        db.close()
        callback()

module.exports = Config
