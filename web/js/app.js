function App () {
  this.controller = new Router();
  this.networkList = new NetworkList();
  Util.bindMessageHandlers(this);
}

App.prototype = {
  _reqid: 0,

  connect: function (password) {
    if (this.socket) {
      return;
    }

    scheme = (window.location.protocol === 'https:') ? 'wss' : 'ws';
    this.socket = new WebSocket(scheme + "://" + window.location.host + "/chat/stream?password=" + password);

    var that = this;

    this.socket.onopen = function(evt) {
      console.info("Connection open ...");
    };

    this.socket.onmessage = function(evt) {
      console.info(evt.data);
      that.processMessage(JSON.parse(evt.data));
    };

    this.socket.onclose = function(evt) {
      console.info("Connection closed.");
    };

    this.socket.onerror = function() {
      console.info("ERROR!", arguments);
    }
  },

  processMessage: function (message) {
    if (message._reqid) {
      // FIXME: Not implemented;
      return;
    }

    if (message.cid) {
      // backbone uses 'cid' internally, so use 'nid' instead.
      message.nid = message.cid;
      message.cid = null;
    }

    var type = message.type;
    if (this.messageHandlers[type]) {
      this.messageHandlers[message.type].apply(this, [ message ]);
    }

    if (message.nid) {
      var network = this.networkList.get(message.nid);
      if (network) {
        network.processMessage(message);
      }
    }
  },

  idleReconnect: function () {
    console.info('idle! reconnect!');
  },

  send: function (message) {
    console.info("sending:", message);
    this.socket.send(JSON.stringify(message));
    this._reqid ++;
  },

  messageHandlers: {
    header: function (message) {
      this.timeOffset   = new Date().getTime() - message.time;
      this.maxIdle      = message.idle_interval;
      // this.idleInterval = setInterval(_.bind(this.idleReconnect, this), this.maxIdle)
    },

    stat_user: function (message) {
      if (!this.user)
        this.user = new User(message);
      else
        this.user.set(message);
    },

    makeserver: function (message) {
      message.id = message.nid;
      this.networkList.add(message);
    },

    backlog_complete: function (message) {
      // FIXME: Do anything here?
    },

    heartbeat_echo: function (message) {
      // FIXME: Need to implement this
      console.warn('Ignoring heartbeat echo');
      console.warn(message);
    },

    idle: function (message) {
      /* ignore, lastMessageTime will still be updated above. */
    },
  }
};