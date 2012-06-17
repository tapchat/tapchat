Crypto  = require('crypto')
Request = require('request')
Base64  = require('../base64')

Log                = require './log'
ConsoleBuffer      = require './console_buffer'
ChannelBuffer      = require './channel_buffer'
ConversationBuffer = require './conversation_buffer'

NOTIFY_URL = 'https://tapchat.heroku.com/notify'

class PushClient
  constructor: (engine) ->
    @engine = engine

  sendPush: (message, callback) ->
    # FIXME: This needs to also confirm the client is still connected.
    # if ($bid eq $self->{selected_buffer}) {
    #    return;
    # }

    connection = @engine.findConnection(message.cid)
    buffer     = connection.findBuffer(message.bid)

    #unless ($server->{usermode_away} == 1) {
    #    return;
    #}

    title = buffer.name

    text = null
    if buffer instanceof ChannelBuffer
      text = "<#{message.from}> #{message.msg}"
    else
      text = message.msg

    info =
      title: title
      text:  text
      cid:   message.cid
      bid:   message.bid

    json = JSON.stringify(info)

    Log.info "Sending push notification: #{json}"

    # Push notifications go to the TapChat server, then to UrbanAirship,
    # then to Google (C2DM). None of these people need to know what you're
    # saying.
    [ iv, ciphertext ] = @encrypt(@engine.pushKey, json)

    body =
      id:      @engine.pushId
      message: Base64.urlEncode(ciphertext)
      iv:      Base64.urlEncode(iv)

    Request.post
      url: NOTIFY_URL
      form: body,
      (err, response, body) =>
        unless response.statusCode.toString().match(/^2/)
          Log.error("Error sending push notification: #{response.statusCode}")
        callback() if callback

  encrypt: (key, msg) ->
    iv     = Crypto.randomBytes(16)
    cipher = Crypto.createCipheriv('aes-256-cbc', key.toString('binary'), iv.toString('binary'))

    ciph  = cipher.update msg, 'utf8', 'binary'
    ciph += cipher.final()

    return [ iv, new Buffer(ciph, 'binary') ]

module.exports = PushClient