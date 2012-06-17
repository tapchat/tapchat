Winston = require 'winston'

log = new Winston.Logger
  transports: [
    new Winston.transports.Console
      timestamp: true
      level: 'info'
  ]

log.setLevel = (level) =>
  for name, transport of log.transports
    transport.level = level

module.exports = log