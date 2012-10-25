Winston = require 'winston'

log = new Winston.Logger
  transports: [
    new Winston.transports.Console
      timestamp: true
      level: 'info'
  ]

log.setLevel = (level) ->
  @level = level
  for name, transport of @transports
    transport.level = level

module.exports = log