Crypto  = require('crypto')
Request = require('request')
Base64  = require('../base64')

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

    console.log 'Sending push notification:', message

    title = buffer.name

    text = null
    if buffer.type == 'channel'
      text = "<#{message.from}> #{message.msg}"
    else
      text = message.msg

    info =
      title: title
      text:  text
      cid:   message.cid
      bid:   message.bid

    # Push notifications go to the TapChat server, then to UrbanAirship,
    # then to Google (C2DM). None of these people need to know what you're
    # saying.
    [ iv, ciphertext ] = @encrypt(@engine.pushKey, JSON.stringify(info))

    console.log 'iv wat', iv.toString('base64')
    console.log 'iv wat', Base64.urlEncode(iv.toString('binary'))
    console.log 'iv waa', Base64.encode(iv)
    console.log 'iv waa', Base64.urlEncode(iv)

    body =
      id:      @engine.pushId
      message: Base64.urlEncode(ciphertext)
      iv:      Base64.urlEncode(iv)

    console.log('POST', body)

    Request.post
      url: NOTIFY_URL
      form: body,
      (err, response, body) =>
        unless response.statusCode.toString().match(/^2/)
          console.log("Error sending push notification: #{response.statusCode}")
        callback() if callback

  encrypt: (key, msg) ->
    iv     = Crypto.randomBytes(16)
    cipher = Crypto.createCipheriv('aes-256-cbc', key.toString('binary'), iv.toString('binary'))

    ciph  = cipher.update msg, 'utf8', 'binary'
    ciph += cipher.final()

    console.log('ciph', ciph)
    console.log('iv', iv)

    return [ iv, new Buffer(ciph, 'binary') ]

module.exports = PushClient