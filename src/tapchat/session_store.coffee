Fs = require 'fs'
_  = require('underscore')

class SessionStore
  constructor: (fileName) ->
    @fileName = fileName
    if Fs.existsSync(@fileName)
      @sessions = JSON.parse(Fs.readFileSync(@fileName).toString())
    else
      @sessions = {}

  all: () ->
    _.clone(@sessions)

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