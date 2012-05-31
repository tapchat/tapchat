function App () {
  this.controller = new Router();
  this.networkList = new NetworkList();
  Util.bindMessageHandlers(this);
}

App.prototype = {
  _reqid: 0,

  processMessage: function (message) {
    var target = this;
    
    // backbone uses 'cid' internally, so use 'nid' instead.
    if (message.cid) {
      message.nid = message.cid;
      message.cid = null;
    }
    
    // HACK HACK
    if (message.type == 'server_motd') {
      message.nid = this.networkList.find(function (network) {
        return network.bufferList.any(function (buffer) {
          return buffer.id == message.bid;
        });
      }).id;
    }

    // Network and buffer-specific messages are delegated to cooresponding model.
    if (message.nid && message.type != 'makeserver') {
      var network = this.networkList.get(message.nid);
      if (network == null)
        throw 'Network not found: ' + message.nid;
      target = network;

      if (message.bid && message.bid > -1 && message.type != 'makebuffer') {
        var buffer = network.bufferList.get(message.bid);
        if (buffer == null) {
          throw 'Buffer not found: ' + message.bid;
        }
        target = buffer;
      }
    }
      
    if (target.messageHandlers[message.type])
      target.messageHandlers[message.type].apply(target, [ message ]);
    else
      throw "Unknown message type: " + message.type + ' (target: ' + target.id + ') ' + JSON.stringify(message);
  },
  
  idleReconnect: function () {
    console.info('idle! reconnect!');
  },
  
  send: function (message) {
    console.info("sending:", message);
    this.socket.send(JSON.stringify(message));
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


$(function () {
  window.app = new App();
  window.app.view = new AppView({
    el: $('#app')
  });

  password = prompt('enter password');
  scheme = (window.location.protocol === 'https:') ? 'wss' : 'ws';
  window.app.socket = new WebSocket(scheme + "://" + window.location.host + "/chat/stream?password=" + password);
  
  window.app.socket.onopen = function(evt) {
    console.info("Connection open ..."); 
  };
  
  window.app.socket.onmessage = function(evt) {
    console.info(evt.data);
    window.app.processMessage(JSON.parse(evt.data)); 
  };
  
  window.app.socket.onclose = function(evt) {
    console.info("Connection closed."); 
  };

  window.app.socket.onerror = function() {
    console.info("ERROR!", arguments);
  }
  
  Backbone.history.start();

  $('#entry input').keypress(function(event) {
    if (event.keyCode == 13) {
      var text = $(this).val();
      $(this).val('');

      if (text == "") return;

      // FIXME
      var network = window.app.controller.current_network;
      var buffer  = window.app.controller.current_buffer;


      var msg = {
            cid: network.get('nid'),
             to: buffer.get('name'),
            msg: text,
         _reqid: window.app._reqid,
        _method: "say"
      };

      window.app.send(msg);

      window.app._reqid ++;
    }
  });
});
