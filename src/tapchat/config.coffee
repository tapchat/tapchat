Program      = require('commander')
WorkingQueue = require('capisce').WorkingQueue
PasswordHash = require('password-hash')
Path         = require 'path'
Fs           = require 'fs'
Mkdirp       = require 'mkdirp'
ChildProcess = require 'child_process'

Config =
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
      Program.password 'Choose a password:', (password) ->
        config.password = PasswordHash.generate(password)
        over()

    queue.perform (over) =>
      Config.generateCert over

    queue.whenDone =>
      Config.saveConfig config, callback

    queue.doneAddingJobs()

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
          callback(JSON.parse(data))
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

module.exports = Config
