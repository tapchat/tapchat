#
# config.coffee
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

Program      = require('commander')
WorkingQueue = require('capisce').WorkingQueue
PasswordHash = require('password-hash')
Path         = require('path')
Fs           = require('fs')
Mkdirp       = require('mkdirp')
ChildProcess = require('child_process')
UUID         = require('node-uuid')
Crypto       = require('crypto')

Config =
  getAppVersion: ->
    JSON.parse(Fs.readFileSync(__dirname + "/../../package.json")).version;

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
      if config
        callback(config)
      else
        Config.setup(callback)

  setup: (callback)->
    console.log 'Welcome to TapChat!'

    config = {}

    queue = new WorkingQueue(1)

    queue.perform (over) =>
      Program.prompt 'Choose a port [8067]: ', (port) ->
        config.port = port || 8067
        over()

    queue.perform (over) =>
      # FIXME: Workaround for https://github.com/visionmedia/commander.js/issues/72
      readline = require('readline')
      if readline.emitKeypressEvents # undocumented API, may change in the future
        readline.emitKeypressEvents(process.stdin)

      Program.password 'Choose a password:', (password) ->
        config.password = PasswordHash.generate(password)
        over()

    queue.perform (over) =>
      Config.generateCert over

    queue.whenDone =>
      Config.verifyConfig config, callback

    queue.doneAddingJobs()

  verifyConfig: (config, callback) ->
    config.push_id  = UUID.v4()                                 unless config.push_id
    config.push_key = Crypto.randomBytes(32).toString('base64') unless config.push_key
    Config.saveConfig config, callback

  generateCert: (callback) ->
    certFile = Config.getCertFile()
    Path.exists certFile, (exists) =>
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
    Path.exists Config.getConfigFile(), (exists) =>
      if exists
        Fs.readFile Config.getConfigFile(), (err, data) =>
          throw err if err
          config = JSON.parse(data)
          Config.verifyConfig(config, callback)
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

module.exports = Config
