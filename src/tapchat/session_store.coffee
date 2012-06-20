Path = require 'path'
Fs   = require 'fs'

class SessionStore
  constructor: (fileName) ->
    @fileName = fileName
    if Path.existsSync(@fileName)
      @sessions = JSON.parse(Fs.readFileSync(@fileName).toString())
    else
      @sessions = {}

  get: (sessionId) ->
    @sessions[sessionId]

  set: (sessionId, session) ->
    @sessions[sessionId] = session
    @save()
    session

  destroy: (sessionId) ->
    delete @sessions[sessionId]
    @save()

  save: ->
    Fs.writeFileSync(@fileName, JSON.stringify(@sessions))

module.exports = SessionStore