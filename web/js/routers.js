var Router = Backbone.Router.extend({
  routes: {
    '':                     'index',
    'settings':             'settings',
    ':networkId':           'network',
    ':networkId/:bufferId': 'buffer',
  },

  index: function () {
    this.buffer(-1, -1);
  },

  settings: function () {
    app.view.showPage(app.settings);
  },

  network: function (networkId) {
    var network = app.networkList.get(networkId);

    this.networkId = networkId;
    this.bufferId  = null;

    if (network) {
      var consoleBufferId = network.bufferList.find(function (buffer) {
        return buffer.get('name') == '*';
      });
      this.buffer(networkId, consoleBufferId);
    }
  },

  buffer: function (networkId, bufferId) {
    if (networkId < 0 || bufferId < 0) {
      app.view.showPage(null);
      return;
    }

    this.networkId = networkId;
    this.bufferId  = bufferId;

    var network = app.networkList.get(networkId);
    if (network) {
      var buffer = network.bufferList.get(bufferId);
      if (buffer) {
        app.view.showPage(buffer.view);
      } else {
        app.view.showPage(null);
      }
    }
  }
});
