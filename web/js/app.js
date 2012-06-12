Backbone.sync = function() {};

function App () {
  this.controller = new Router();
  this.networkList = new NetworkList();
  // Util.bindMessageHandlers(this);
}

_.extend(App.prototype, Backbone.Events, {
  _reqid: 0,

  connect: function (password) {
    if (this.socket) {
      return;
    }

    var scheme  = (window.location.protocol === 'https:') ? 'wss' : 'ws';
    var address = scheme + "://" + window.location.host + "/chat/stream?password=" + encodeURIComponent(password);
    console.log('Websocket address is: ' + address);

    this.socket = new WebSocket(address);

    var that = this;

    this.socket.onopen = function(evt) {
      console.info("Connection open ...");
    };

    this.socket.onmessage = function(evt) {
      console.info(evt.data);
      that.processMessage(JSON.parse(evt.data));
    };

    this.socket.onclose = function(evt) {
      console.info("Websocket connection closed.", evt);
      app.view.showError("Connection closed, please reload.");
    };

    this.socket.onerror = function() {
      console.info("Websocket error:", arguments);
    };
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

  sendHeartbeat: function() {
    // FIXME: Implement
  },

  setConnectionState: function(newState) {
    this.connectionState = newState;
    this.trigger('connection-state-changed', newState);
  },

  messageHandlers: {
    makeserver: function (message) {
      message.id = message.nid;

      var network = this.networkList.get(message.nid);
      if (network) {
        network.reload(message);
      } else {
        this.networkList.add(message);
      }
    },

    connection_deleted: function (message) {
      var network = this.networkList.get(message.nid);
      this.networkList.remove(network);
      network.destroy();
    },

    header: function (message) {
      this.setConnectionState('loading');
    },

    backlog_complete: function (message) {
      this.setConnectionState('loaded');
      this.sendHeartbeat();
    },

    heartbeat_echo: function (message) {
      _.each(message.seenEids, function (buffers, cid) {
        var network = this.networkList.get(cid);
        if (network) {
          _.each(buffers, function (bufferEid, bid) {
            var buffer = network.bufferList.get(bid);
            if (buffer) {
              buffer.markRead(bufferEid);
            }
          });
        }
      });
    },

    idle: function (message) {
      // Ignored
    }
  }
});