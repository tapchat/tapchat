var Router = Backbone.Router.extend({
  routes: {
    '':                     'index',
    'settings':             'settings',
    'admin':                'admin',
    ':networkId':           'network',
    ':networkId/:bufferId': 'buffer'
  },

  index: function () {
    this.buffer(-1, -1);
  },

  settings: function () {
    app.view.showPage(app.settings);
  },

  admin: function() {
    app.view.showPage(app.admin);
  },

  network: function (networkId) {
    this.buffer(networkId, null);
  },

  buffer: function (networkId, bufferId) {
    this.networkId = networkId;
    this.bufferId  = bufferId;

    var network = app.client.connections.get(networkId);
    if (!network) {
      app.view.showPage(null);
      return;
    }

    if (!bufferId) {
      this.bufferId = network.consoleBuffer.id;
    }

    if (this.networkId <= 0 || this.bufferId <= 0) {
      app.view.showPage(null);
      return;
    }

    var buffer = network.buffers.get(this.bufferId);
    if (buffer) {
      app.view.showPage(buffer.view);
    } else {
      app.view.showPage(null);
    }
  }
});
