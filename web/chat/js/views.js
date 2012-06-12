var BUFFER_EVENTS = {
  "socket_closed":         "Disconnected",
  "connecting":            "Connecting",
  "quit_server":           "Quit server",
  "notice":                "{{msg}}",
  "error":                 "Error: {{msg}}",
  "you_nickchange":        "You are now known as {{newnick}}",
  "banned":                "You were banned",
  "connecting_retry":      "Retrying connection in {{interval}} seconds",
  "connecting_failed":     "Failed to connect",
  "connected":             "Connected to {{hostname}}",
  "joining":               "Joining {{channels}}",
  "user_mode":             "Your mode is +{{newmode}}",
  "joined_channel":        "{{nick}} has joined",
  "parted_channel":        "{{nick}} has left",
  "quit":                  "{{nick}} has quit",
  "away":                  "{{nick}} is away",
  "kicked_channel":        "{{nick}} was kicked from {{chan}} by {{kicker}}: {{msg}}",
  "you_joined_channel":    "You have joined",
  "you_parted_channel":    "You have left",
  "channel_mode_is":       "Mode is: {{newmode}}",
  "channel_timestamp":     "Created at: {{timestamp}}",
  "nickchange":            "{{oldnick}} is now known as {{newnick}}",
  "user_channel_mode":     "Mode {{diff}} {{nick}} by {{from}}",
  "channel_url":           "Channel URL: {{url}}",
  "channel_topic":         "Topic is: {{topic}}",
  "channel_topic_cleared": "{{nick}} cleared the topic",
  "channel_mode":          "Channel mode: {{diff}} by {{from}}"
};

var AppView = Backbone.View.extend({
  initialize: function (options) {
    window.app.networkList.bind('add', this.addNetwork, this);
  },

  addNetwork: function (network) {
    var view = new NetworkListRowView({ model: network });
    $('#networks').append(view.render().el);

    network.bufferList.bind('add', this.addBuffer, this);
  },

  addBuffer: function (buffer) {
    view = new BufferView({ model: buffer });
    buffer.view = view;
    $('#pages').append(view.el);

    if (buffer.get('buffer_type') == 'channel') {
      buffer.memberListView = new MemberListView({ model: buffer });
      $('#users').append(buffer.memberListView.render().el);
    }

    var network = buffer.network;
    if (network.pendingOpenBuffer === buffer.get('name')) {
      app.showBuffer(buffer.get('nid'), buffer.get('id'));
      network.pendingOpenBuffer = null;
      return;
    }

    var networkMatches = app.controller.networkId == buffer.network.id;
    var bufferMatches  = app.controller.bufferId  == buffer.id;
    var isConsole      = (!app.controller.bufferId) && (buffer instanceof ConsoleBuffer);
    if (networkMatches && (bufferMatches || isConsole)) {
      app.controller.buffer(app.controller.networkId, app.controller.bufferId);
    }
  },

  showPage: function (pageView) {
    if (this.currentPage) {
      $(this.currentPage.el).removeClass('active');
    }

    this.currentPage = pageView;

    if (pageView) {
      $(pageView.el).addClass('active');
      this.setTitle(pageView.getTitle());
    } else {
      this.setTitle('');
    }

    // This is a bit of a special case hack here...
    var isBuffer = (this.currentPage instanceof BufferView);
    if ((!this.currentPage) || isBuffer) {
      $('#app').removeClass('not-buffer');
    } else {
      $('#app').addClass('not-buffer');
    }

    // FIXME: Move
    app.view.trigger('page-changed', this.currentPage);
  },

  setTitle: function (text) {
    $('#title').html(text);
  },

  showAddNetworkDialog: function () {
    new EditNetworkDialog().show();
  },

  showJoinChannelDialog: function () {
    new JoinChannelDialog().show();
  },

  showLoginDialog: function () {
    var content = ich.LoginDialog();
    var dialog = bootbox.dialog(content, {
      "label" : "Login",
      "class" : "btn-primary",
      "callback": function() {
          var password = dialog.find("input[type=password]").val();
          if (password.length === 0) {
            return false;
          }
          app.connect(password);
          return true;
      }
    }, {
      "animate": false,
      "backdrop": "static"
    });

    dialog.find("input[type=password]").focus();
  },

  showError: function (text) {
    var dialog = bootbox.modal(text, "Error", {
      "animate": false,
      "backdrop": "static",
      "headerCloseButton": null
    });
  }
});

var NetworkListRowView = Backbone.View.extend({
  tagName: 'li',

  initialize: function () {
    this.model.bind('change', this.render, this);
    this.model.bind('destroy', this.remove, this);
    this.model.bufferList.bind('add', this.addBuffer, this);

    this.render();

    app.view.on('page-changed', this.pageChanged, this);
  },

  pageChanged: function(page) {
    if (page && page.model && page.model === this.model.getConsoleBuffer()) {
      $(this.el).addClass('active');
    } else {
      $(this.el).removeClass('active');
    }
  },

  addBuffer: function (buffer) {
    // 'console' buffers are a special case
    if (buffer.get('name') == '*') {
      return;
    }

    var bufferListView = new BufferListRowView({ model: buffer });
    this.$('.bufferList').append(bufferListView.render().el);
  },

  select: function () {
    $('#networks li').removeClass('active');
    $(this.el).addClass('active');
  },

  render: function () {
    $(this.el).empty();
    $(this.el).append(ich.NetworkListRowView({
      name: this.model.get('name')
    }));

    var url = '#' + this.model.id;
    $(this.el).find('a.networkInfo').tappable(function () {
      window.location = url;
    });

    return this;
  }
});

var BufferListRowView = Backbone.View.extend({
  tagName: 'li',

  initialize: function () {
    $(this.el).attr('id', 'buffer-' + this.model.id);

    this.model.bind('change', this.render, this);
    this.model.bind('hidden', this.hide, this);
    this.model.bind('destroy', this.remove, this);

    app.view.on('page-changed', this.pageChanged, this);

    if (this.model.get('hidden')) {
      $(this.el).addClass('archived');
    }
  },

  pageChanged: function(page) {
    if (page && page.model === this.model) {
      $(this.el).addClass('active');
    } else {
      $(this.el).removeClass('active');
    }
  },

  select: function () {
    $('#networks li').removeClass('active');
    $(this.el).addClass('active');
  },

  hide: function () {
    $(this.el).addClass('archived');
    this.render();
  },

  render: function () {
    var network = app.networkList.get(this.model.get('nid'));
    var url = '#' + network.id + '/' + this.model.id;

    var a = $('<a>').addClass('tappable').html(this.model.get('name'));

    $(this.el).empty();
    $(this.el).append(a);

    a.tappable(function () {
      window.location = url;
    });

    return this;
  }
});

var MemberListView = Backbone.View.extend({
  tagName: 'ul',
  className: 'unstyled',

  initialize: function () {
    // FIXME: Is it OK to have '#' in ID?
    this.el.id = 'users-' + this.model.get('name');

    app.view.on('page-changed', this.pageChanged, this);

    this.model.bind('destroy', this.remove, this);
    this.model.memberList.bind('add', this.addMember, this);
  },

  pageChanged: function(page) {
    if (page && page.model === this.model) {
      $(this.el).addClass('active');
    } else {
      $(this.el).removeClass('active');
    }
  },

  addMember: function (member) {
    var view = new MemberListRowView({ model: member });
    $(this.el).append(view.render().el);
  }
});

var MemberListRowView = Backbone.View.extend({
  tagName: 'li',

  initialize: function () {
    this.model.bind('change', this.render, this);
    this.model.bind('destroy', this.remove, this);
  },

  render: function () {
    $(this.el).attr('class', this.model.get('op') ? 'op' : '');

    var data = this.model.toJSON();
    data.url = "javascript:alert('not implemented')"; // FIXME
    $(this.el).html(ich.MemberListRowView(data));
    return this;
  }
});

var BufferView = Backbone.View.extend({
  className: 'page buffer',

  initialize: function () {
    $(this.el).append(ich.BufferView());

    var self = this;
    this.$('.entry input').keypress(function(event) {
      if (event.keyCode == 13) {
        var text = $(this).val();
        $(this).val('');
        self.sendMessage(text);
      }
    });

    app.view.on('page-changed', this.pageChanged, this);

    this.el.id = 'buffer-' + this.model.get('id');

    this.model.bind('change',  this.render,   this);
    this.model.bind('event',   this.addEvent, this);
    this.model.bind('destroy', this.remove,   this);
  },

  getTitle: function () {
    if (this.model instanceof ConsoleBuffer) {
        return this.model.network.get('name');
    } else {
      return this.model.get('name');
    }
  },

  render: function () {
    var topic = this.model.get('topic_text');
    if (topic) {
      $(this.el).find('.topic_text').html(topic);
    } else {
      $(this.el).find('.topic_text').html('');
    }
    return this;
  },

  pageChanged: function (page) {
    if (this === page) {
      this.scrollToBottom();
      this.$('.entry input').focus();
    }
  },

  addEvent: function (event) {
    var text;

    var template = BUFFER_EVENTS[event.type];
    if (template) {
      text = _.template(template, event);
    } else if (event.msg) {
      text = event.msg;
    }

    if (text) {
      var rendered = ich.buffer_event({
        datetime: Util.explodeDateTime(new Date(event.time*1000)),
        from:     event.nick || event.from,
        msg:      text,
        type:     event.type
      });
      $(rendered).find('a').linkify({
        handleLinks: function (links) {
          return links.prop('target', '_new');
        }
      });
      $(this.el).find('.events').append(rendered);

      this.scrollToBottom();
    }
  },

  scrollToBottom: function () {
    this.$('.events').scrollTop(this.$('.events')[0].scrollHeight);
  },

  sendMessage: function (text) {
    if (text === "") return;
    var buffer = this.model;
    var msg = {
          cid: buffer.network.get('nid'),
           to: buffer.get('name'),
          msg: text,
       _reqid: window.app._reqid,
      _method: "say"
    };
    window.app.send(msg);
  }
});

var MainMenuView = Backbone.View.extend({
  initialize: function (options) {
    window.app.networkList.bind('add', this.addNetwork, this);
  },

  addNetwork: function (network) {
    var view = new NetworkListRowView({ model: network });
    $('#main-menu').prepend(view.render().el);
  }
});

var SettingsView = Backbone.View.extend({
  id: 'page-settings',
  className: 'page',

  initialize: function (options) {
    $(this.el).append(ich.Settings);

    app.view.on('page-changed', this.pageChanged, this);
    app.networkList.bind('add', this.addNetwork, this);

    this.$('#add-network-btn').click(function () {
      app.view.showAddNetworkDialog();
    });
  },

  addNetwork: function (network) {
    var networkView = new SettingsNetworkView({
      model: network
    });
    $('#networks-list').append(networkView.render().el);
  },

  pageChanged: function(page) {
    if (page === this) {
      $('#settings-btn').addClass('active');
      $('#settings-item').parent('li').addClass('active');
    } else {
      $('#settings-btn').removeClass('active');
      $('#settings-item').parent('li').removeClass('active');
    }
  },

  getTitle: function() {
    return 'Settings';
  }
});

var SettingsNetworkView = Backbone.View.extend({
  tagName: 'li',

  events: {
    'click .btn-connect':    'connect',
    'click .btn-disconnect': 'disconnect',
    'click .btn-edit':       'openEditDialog',
    'click .btn-remove':     'deleteConnection'
  },

  initialize: function (options) {
    $(this.el).attr('id', 'network-' + this.model.id);
    this.model.on('change', this.render, this);
    this.model.bind('destroy', this.remove, this);
  },

  render: function () {
    var isDisconnected = this.model.get('state') == 'disconnected';
    $(this.el).empty();
    $(this.el).append(ich.SettingsNetworkView({
      name:           this.model.get('name'),
      state:          this.model.get('state'),
      isConnected:    !isDisconnected,
      isDisconnected: isDisconnected
    }));
    return this;
  },

  connect: function () {
    this.model.reconnect();
  },

  disconnect: function () {
    this.model.disconnect();
  },

  deleteConnection: function () {
    if (confirm("Are you sure?")) {
      this.model.deleteConnection();
    }
  },

  openEditDialog: function () {
    new EditNetworkDialog({ model: this.model }).show();
  }
});

var EditNetworkDialog = Backbone.View.extend({
  events: {
    'change input[name=ssl]': 'sslChanged'
  },

  render: function () {
    $(this.el).empty();
    $(this.el).append(ich.AddNetworkDialog());

    if (this.model) {
      var self = this;
      _.each(this.model.attributes, function(val, key) {
        if (key === 'nick') key = 'nickname'; // Argh
        var input = $(self.el).find('input[name=' + key + ']');
        if (input.attr('type') === 'checkbox') {
          input.attr('checked', val);
        } else {
          input.val(val);
        }
      });
    }

    return this;
  },

  show: function () {
    var self = this;
    this.dialog = bootbox.dialog(this.render().el,
      [
        {
          "label": this.model ? 'Save Network' : 'Add Network',
          "class": "btn-primary",
          callback: function () { return self.onSubmit(); }
        },
        {
          "label": "Cancel",
          "class": "btn"
        }
      ],
      {
        header: this.model ? 'Edit IRC Network' : 'Add IRC Network',
        animate: false,
        backdrop: "static"
      }
    );
    this.dialog.find('input[name=hostname]').focus();
  },

  sslChanged: function (e) {
    var checked = $(e.target).is(':checked');
    console.log('checked', checked);
    console.log( $(this.el).find('input[name=port]') );
    $(this.el).find('input[name=port]').attr('placeholder', checked ? 'port' : '6667');
  },

  onSubmit: function () {
    var form = $(this.dialog.find('form'));

    var valid = _.reduce(form.find('input[type=text]'), function (valid, input) {
      input = $(input);

      // Only require port number if using SSL
      if (input.attr('name') === 'port') {
        var isSSL = (form.find('input[name=ssl]').is(':checked'));
        if (!isSSL) {
          input.removeClass('error');
          return valid;
        }
      }

      if (_.isEmpty(input.val())) {
        input.addClass('error');
        return false;
      } else {
        input.removeClass('error');
        return valid && true;
      }
    }, true);

    if (!valid) {
      return false;
    }

    var data = form.serializeObject();
    data.ssl = !!data.ssl;
    if (_.isEmpty(data.port)) {
      data.port = 6667;
    }

    if (this.model) {
      data._method = 'edit-server';
      data.cid = this.model.id;
    } else {
      data._method = 'add-server';
    }

    console.log('form', data);
    app.send(data);
  }
});

var JoinChannelDialog = Backbone.View.extend({
  render: function () {
    $(this.el).empty();
    $(this.el).append(ich.JoinChannelDialog({
      networks: app.networkList.models.map(function (m) {
        return m.attributes;
      })
    }));
    return this;
  },

  show: function () {
    var self = this;
    this.dialog = bootbox.dialog(this.render().el,
      [
        {
          "label": "Join",
          "class": "btn-primary",
          callback: function () { return self.onSubmit(); }
        },
        {
          "label": "Cancel",
          "class": "btn"
        }
      ],
      {
        "header": "Join Channel",
        "animate": false,
        "backdrop": "static"
      }
    );
    this.dialog.find('input[name=channel]').focus();
  },

  onSubmit: function() {
    var networkId = $(this.dialog).find('select[name=network]').val();
    var channel   = $(this.dialog).find('input[name=channel]').val();

    var network = app.networkList.get(networkId);
    network.join(channel);
  }
});