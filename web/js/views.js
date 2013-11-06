var AppView = Backbone.View.extend({
  initialize: function (options) {
    window.app.client.connections.bind('add', this.addNetwork, this);
  },

  addNetwork: function (network) {
    var view = new NetworkListRowView({ model: network });
    $('#networks').append(view.render().el);

    network.buffers.bind('add', this.addBuffer, this);
  },

  addBuffer: function (buffer) {
    view = new BufferView({ model: buffer });
    buffer.view = view;
    $('#pages').append(view.el);

    if (buffer.get('buffer_type') == 'channel') {
      buffer.memberListView = new MemberListView({ model: buffer });
      $('#users').append(buffer.memberListView.render().el);
    }

    var network = buffer.connection;
    if (network.pendingOpenBuffer === buffer.get('name')) {
      app.showBuffer(buffer.get('_cid'), buffer.get('id'));
      network.pendingOpenBuffer = null;
      return;
    }

    var networkMatches = app.controller.networkId == buffer.connection.id;
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
      this.setTopic(pageView.getTopic());
    } else {
      this.setTitle('');
      this.setTopic('');
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
    if (this.currentPage) {
      this.currentPage.render(); 
    }

    if (isBuffer) {
      var buffer = this.currentPage.model;
      app.client.selectBuffer(buffer.connection.id, buffer.id, true);
    } else {
      app.client.selectBuffer(0, 0, false)
    }
  },

  setTitle: function (text) {
    if (_.isEmpty(text)) {
      $('.page-title').text('TapChat');
      document.title = 'TapChat';
    } else {
      $('.page-title').text(text);
      document.title = text + ' - TapChat';
    }
  },

  setTopic: function(text) {
    $('.page-topic').text(text);
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
          var username = dialog.find("input[type=text]").val();
          var password = dialog.find("input[type=password]").val();
          if (password.length === 0) {
            return false;
          }
          $.post('/chat/login', { username: 'user', username: username, password: password }, function (data) {
            $.cookie('session', data.session, {secure: true});
            app.client.connect();
          })
          .error(function() {
            app.view.showLoginDialog();
          });
          return true;
      }
    }, {
      "animate": false,
      "backdrop": "static"
    });

    dialog.find("input[type=text]").focus();
  },

  showCertDialog: function (message) {
    new CertDialog(message).show();
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
    this.model.buffers.bind('add', this.addBuffer, this);
    app.view.on('page-changed', this.pageChanged, this);
    
    $(this.el).append(ich.NetworkListRowView({
      name: this.model.get('name')
    }));
    var url = '#' + this.model.id;
    $(this.el).find('a.networkInfo').tappable(function () {
      window.location = url;
    });

    this.render();
  },

  pageChanged: function(page) {
    if (page && page.model && page.model === this.model.consoleBuffer) {
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
    this.$('.bufferList').appendSorted(bufferListView.render().el);
  },

  select: function () {
    $('#networks li').removeClass('active');
    $(this.el).addClass('active');
  },

  render: function () {
    this.updateStatusClass();
    return this;
  },

  updateStatusClass: function() {
    var status = this.model.get('status');
    if ($(this.el).hasClass('status-'+status)) {
      return;
    }
    var classes = $(this.el).attr('class');
    if (classes) {
      $(this.el).attr('class', classes.split(' ').filter(function(item) {
        return item.indexOf('status-') === -1;
      }).join(' '));
    }
    $(this.el).addClass('status-' + status);
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
    var network = app.client.connections.get(this.model.get('_cid'));
    var url = '#' + network.id + '/' + this.model.id;

    var highlights = this.model.get('highlights');
    if (highlights == 0) {
      highlights = '';
    }

    var a = $('<a>').addClass('tappable').text(this.model.get('name'));
    a.append($('<span>').addClass('badge badge-important').text(highlights));

    $(this.el).empty();
    $(this.el).append(a);

    a.tappable(function () {
      window.location = url;
    });

    if ((this.model instanceof ChannelBuffer)) {
      if (!this.model.get('joined')) {
        $(this.el).addClass('not-joined');
      } else {
        $(this.el).removeClass('not-joined');
      }
    }

    this.$el.toggleClass('archived', !!this.model.get('archived'));

    if (this.model.get('unread')) {
      $(this.el).addClass('unread');
    } else {
      $(this.el).removeClass('unread');
    }

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
    this.model.members.bind('add', this.addMember, this);
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
    $(this.el).appendSorted(view.render().el);
  }
});

var MemberListRowView = Backbone.View.extend({
  tagName: 'li',

  initialize: function () {
    this.model.bind('change', this.render, this);
    this.model.bind('destroy', this.remove, this);
  },

  render: function () {
    if (this.model.has('mode')) {
      $(this.el).attr('class', 'mode-' + this.model.get('mode'));
    }

    var self = this;

    var nick = this.model.get('nick');

    var a = $('<a>')
      .attr('title', nick)
      .attr('href', '#')
      .text(nick)
      .click(function() {
        self.model.buffer.connection.openBuffer(nick, '');
        return false;
      });

    this.$el.empty();
    this.$el.append(a);

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

    this.model.connection.bind('change', this.render, this);

    this.model.bind('change',  this.render, this);
    this.model.bind('destroy', this.remove, this);

    this.model.backlog.bind('add', this.addEvent, this);

    // This is all a big hack.
    this.$('.load-more').click(function() {
      var minEid = self.model.backlog.minEid;
      var params = $.param({cid: self.model.connection.id, bid: self.model.id, num: 150, beforeid: minEid});
      $.getJSON('/chat/backlog?' + params, function(events) {
        var divider = $('<hr>');
        $(self.el).find('.events').prepend(divider);
        var lastEvent = null;
        var eventsToPrepend = [];
        _.each(events, function (eventJson) {
          if (eventJson.msg || Buffer.EVENT_TEXTS[eventJson.type]) {
            var item = new BufferEventItem(eventJson);
            if (lastEvent && lastEvent.shouldMerge(item)) {
              lastEvent.items.add(item);
            } else {
              lastEvent = new BufferEvent(item);
              eventsToPrepend.push(lastEvent);
            }
          }
        });
        _.chain(eventsToPrepend).reverse().each(function(item) {
          self.model.backlog.add(item, { at: 0 });
        });
        divider[0].scrollIntoView();
      });
    });
  },

  getTitle: function () {
    if (this.model instanceof ConsoleBuffer) {
        return this.model.connection.get('name');
    } else {
      return this.model.get('name');
    }
  },

  getTopic: function() {
    if (this.model instanceof ChannelBuffer) {
      var topic = this.model.get('topic');
      if (topic) {
        return topic.topic_text;
      }
    }
    return null;
  },

  render: function () {
    var statusBar = $(this.el).find('.status')

    var status = this.model.connection.get('status');

    if (status != Connection.STATUS_CONNECTED) {
      statusBar.find('.status-text').text(status);
      statusBar.show();
    } else {
      if ((this.model instanceof ChannelBuffer) && (!this.model.get('joined'))) {
        statusBar.find('.status-text').text('Not in channel.');
        statusBar.show();
      } else {
        statusBar.hide(); 
      }
    }
    
    return this;
  },

  pageChanged: function (page) {
    if (this === page) {
      this.scrollToBottom();
      this.$('.entry input').focus();
    }
  },

  addEvent: function (event, collection, options) {
    var view = new BufferEventView({ model: event });
    if (options && options.at == 0) {
      $(this.el).find('.events').prepend(view.render().el);
    } else {
      $(this.el).find('.events').append(view.render().el);
      this.scrollToBottom();
    }
  },

  scrollToBottom: function () {
    this.$('.events').scrollTop(this.$('.events')[0].scrollHeight);
  },

  sendMessage: function (text) {
    if (text === "") return;
    if (text.indexOf('/') == 0 && text.indexOf('/me ') == -1) {
      text = text.substring(1);
      switch (text) {
        case "part":
          this.model.part();
          break;
        case "archive":
          this.model.archive();
          break;
        case "unarchive":
          this.model.unarchive();
          break;
        default:
          alert('Unknown command');
      }
      return;
    }
    this.model.say(text);
  }
});

var BufferEventView = Backbone.View.extend({
  className: 'event',

  events: {
    'click': 'toggleCollapsed'
  },

  initialize: function () {
    this.model.bind('change', this.render, this);
  },

  render: function() {
    var self = this;
    this.$el.empty();

    if (this.model.items.length > 1) {
      this.$el.addClass('collapsed');
      var summaryEl = this.renderSummary();
      self.$el.append(summaryEl);
    }

    this.model.items.each(function (eventItem) {
      var eventItemEl = self.renderEventItem(eventItem.attributes);
      self.$el.append(eventItemEl);
    });
    return this;
  },

  renderEventItem: function(eventItem) {
    var msg;

    var template = Buffer.EVENT_TEXTS[eventItem.type];
    if (template) {
      msg = _.template(template, eventItem);
    } else if (eventItem.msg) {
      msg = eventItem.msg;
    } else {
      throw 'Unknown event type: ' + eventItem.type; /// eh?
    }

    var timestamp = new Date(eventItem.time*1000).format("shortTime");
    var from      = eventItem.nick || eventItem.from;
    var type      = eventItem.type;

    var eventDiv = $('<div>')
      .addClass('event_item')
      .addClass('event_item_'+type)
      .append($('<div>').addClass('when')
        .append($('<div>').text(timestamp)));

    if (eventItem.highlight) {
      eventDiv.addClass('highlight');
    }

    var linkifyCfg = {
      handleLinks: function(links) {
        return links.prop('target', '_new');
      }
    };

    var self = this;

    if (type == 'buffer_msg') {
      eventDiv.append($('<div>').addClass('content')
        .append($('<a>').attr('href', '#').addClass('who').text(from).click(function() {
          self.model.connection.openBuffer(from, '');
          return false;
        }))
        .append($('<span>').addClass('message').text(msg).linkify(linkifyCfg)));
    } else if (type == 'buffer_me_msg') {
      eventDiv.append($('<span>').addClass('content')
        .append($('<a>').attr('href', '#').addClass('who').text('• ' + from).click(function() {
          self.model.connection.openBuffer(from, '');
          return false;
        }))
        .append($('<span>').text(msg).linkify(linkifyCfg)));
    } else {
      eventDiv.append($('<div>').addClass('content').append($('<span>').addClass('message').text(msg)));
    }

    return eventDiv;
  },

  renderSummary: function() {
    var self = this;

    var summaryEl = $('<div>')
      .addClass('event_item')
      .addClass('summary');

    var timestamp = new Date(this.model.items.first().get('time')*1000).format("shortTime");
    summaryEl
      .append($('<div>').addClass('when')
      .append($('<div>').text(timestamp)));

    var presenceChanges = {};
    var nickChanges = [];

    this.model.items.each(function(item) {
      var itemType = item.get('type');
      var presence_types = ['joined_channel', 'parted_channel', 'quit'];
      if (_.contains(presence_types, itemType)) {
        presenceChanges[item.get('nick')] = itemType;
      } else if (itemType === 'nickchange') {
        var oldnick = item.get('oldnick')
        var newnick = item.get('newnick')
        if (presenceChanges[oldnick] && presenceChanges[oldnick] === 'joined_channel') {
          var presence = presenceChanges[oldnick];
          delete presenceChanges[oldnick];
          presenceChanges[newnick] = presence;
        }
        nickChanges.push([oldnick, newnick]);
      }
    });

    var strings = [];
    var seenNicks = [];

    self.appendPresenceEvents(strings, presenceChanges, 'joined_channel', 'Joined: ', nickChanges, seenNicks);
    self.appendPresenceEvents(strings, presenceChanges, 'parted_channel', 'Parted: ', nickChanges, seenNicks);
    self.appendPresenceEvents(strings, presenceChanges, 'quit',           'Quit: ',   nickChanges, seenNicks);

    _.each(nickChanges, function(nickChange) {
      if ((!_.contains(seenNicks, nickChange[0])) && (!_.contains(seenNicks, nickChange[1]))) {
        var chain = self.getNickChain(nickChanges, nickChange[0]);
        _.each(chain, function(nick) { seenNicks.push(nick) });
        var firstNick = chain[0];
        var lastNick = _.last(chain);
        strings.push(firstNick + ' → ' + lastNick);
      }
    });

    var contentEl = $('<div>')
      .addClass('content')
      .text(strings.join(' • '));

    summaryEl.append(contentEl);

    return summaryEl;
  },

  appendPresenceEvents: function(strings, presenceChanges, type, textPrefix, nickChanges, seenNicks) {
    var self = this;

    var nicks = _.chain(presenceChanges).keys().filter(function(nick) {
      return presenceChanges[nick] === type;
    });

    if (_.isEmpty(nicks)) {
      return;
    }

    nicks = _.map(nicks, function(nick) {
      var nickChain = self.getNickChainReverse(nickChanges, nick);
      if (nickChain.length <= 1) {
        return nick;
      }
      // Last item is current nick
      nickChain.splice(nickChain.length - 1, 1);

      // Don't need to show nick change if included in presence event
      _.each(nickChain, function(nick) { seenNicks.push(nick); });

      return nick + ' (was ' + nickChain.join(', ') + ')';
    });

    strings.push(textPrefix + nicks.join(', '));
  },

  getNickChain: function(nickChanges, startNick) {
    var chain = [startNick];
    _.each(nickChanges, function(nickChange) {
      var lastNick = _.last(chain);
      if (nickChange[0] === lastNick) {
        chain.push(nickChange[1]);
      }
    });
    return chain;
  },

  getNickChainReverse: function(nickChanges, endNick) {
    var chain = [endNick];
    _.chain(nickChanges).reverse().each(function(nickChange) {
      var lastNick = _.last(chain);
      if (nickChange[1] === lastNick) {
        chain.push(nickChange[0]);
      }
    });
    chain.reverse();
    return chain;
  },

  toggleCollapsed: function() {
    if (this.model.items.length > 1) {
      this.$el.toggleClass('collapsed');
      this.el.scrollIntoView();
    }
  }
});

var MainMenuView = Backbone.View.extend({
  initialize: function (options) {
    window.app.client.connections.bind('add', this.addNetwork, this);
    window.app.client.bind('user-updated', this.updateUser, this);
  },

  addNetwork: function (network) {
    network.bind('open-buffer', this.openBuffer, this);
    var view = new NetworkListRowView({ model: network });
    $('#main-menu').prepend(view.render().el);
  },

  updateUser: function (user) {
    $('#nav .username').text(user.name);
    $('#admin-item').toggleClass('hide', !user.is_admin);
  },

  openBuffer: function(buffer) {
    window.location = '#' + buffer.connection.id + '/' + buffer.id;
    app.view.showPage(buffer.view);
  }
});

var SettingsView = Backbone.View.extend({
  id: 'page-settings',
  className: 'page page-full',

  initialize: function (options) {
    $(this.el).append(ich.Settings);

    app.view.on('page-changed', this.pageChanged, this);
    app.client.connections.bind('add', this.addNetwork, this);

    this.$('.nav-tabs a').click(function (e) {
      e.preventDefault();
      $(this).tab('show');
    });

    this.$('#add-network-btn').click(function () {
      app.view.showAddNetworkDialog();
    });

    this.$('#change-password-form').submit(function () {
      $.post('/chat/change-password', $(this).serializeObject(), function (data) {
        $('#change-password-form input[type="password"]').val('');
        alert('password changed!');
      })
      .error(function(res) {
        var error = JSON.parse(res.responseText).message;
        alert(error);
      });

      return false;
    });
  },

  addNetwork: function (network) {
    var networkView = new SettingsNetworkView({
      model: network
    });
    $('#networks-list').append(networkView.render().el);
  },

  getTitle: function() {
    return 'Settings';
  },

  getTopic: function() {
    return null;
  }
});

var AdminView = Backbone.View.extend({
  id: 'page-admin',
  className: 'page page-full',

  events: {
    'click #btn-admin-add-user': 'showAddUserDialog'
  },

  initialize: function (options) {
    app.view.on('page-changed', this.pageChanged, this);
    app.client.on('users-changed', this.loadUsers, this);
    $(this.el).append(ich.Admin);
  },

  render: function() {
    var list = this.$('#admin-users-list');
    list.empty();
    if (this.users) {
      this.users.forEach(function(user) {
        var editLink = $('<a>').attr('href', '#').text('Edit');
        editLink.tappable(function() {
          new AdminEditUserDialog({model: user}).show();
        });

        var deleteLink = $('<a>').attr('href', '#').text('Delete');
        deleteLink.tappable(function() {
          if (confirm("Are you sure?")) {
            $.ajax('/admin/users/' + user.id, { type: 'DELETE' })
              .success(function(data) {
                app.trigger('users-changed');
              })
              .error(function(res) {
                alert(res.responseText);
             });
          }
        });

        var li = $('<li>');
        li.append(user.name);
        li.append(' &mdash; ');
        li.append(editLink);
        li.append('&nbsp;');
        li.append(deleteLink);
        list.append(li);
      });
    }
    return this;
  },

  getTitle: function() {
    return 'Admin';
  },

  getTopic: function() {
    return null;
  },

  loadUsers: function() {
    var self = this;
    console.log('get users!');
    $.getJSON('/admin/users', function(users) {
      self.users = users;
      self.render();
    });
  },

  showAddUserDialog: function() {
    new AdminEditUserDialog().show();
  },

  pageChanged: function(page) {
    if (page === this) {
      this.loadUsers();
    }
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
    var isDisconnected = this.model.get('status') == 'disconnected';
    $(this.el).empty();
    $(this.el).append(ich.SettingsNetworkView({
      name:           this.model.get('name'),
      state:          this.model.get('status'),
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
    app.client.send(data);
  }
});

var CertDialog = Backbone.View.extend({
  initialize: function (attrs) {
    this.attrs = attrs;
  },

  render: function () {
    $(this.el).empty();
    $(this.el).append(ich.CertDialog(this.attrs));
    return this;
  },

  show: function () {
    var self = this;
    this.dialog = bootbox.dialog(this.render().el,
      [
        {
          "label": "Accept",
          "class": "btn btn-primary",
          "callback": function () { return self.acceptCert(true); }
        },
        {
          "label": "Reject",
          "class": "btn btn-danger",
          "callback": function() { return self.acceptCert(false); }
        }
      ],
      {
        "header": "Accept SSL Certificate?",
        "animate": false,
        "backdrop": "static"
      }
    );
  },

  acceptCert: function (accept) {
    console.log('accept!', this.attrs);
    app.client.send({
      _method:     'accept-cert',
      cid:         this.attrs._cid,
      fingerprint: this.attrs.fingerprint,
      accept:      accept
    });
  }
});

var JoinChannelDialog = Backbone.View.extend({
  render: function () {
    $(this.el).empty();
    $(this.el).append(ich.JoinChannelDialog({
      networks: app.client.connections.models.map(function (m) {
        return { id: m.id, name: m.get('name') };
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

    var network = app.client.connections.get(networkId);
    network.join(channel);
  }
});

var AdminEditUserDialog = Backbone.View.extend({
  events: {
  },

  render: function () {
    $(this.el).empty();
    $(this.el).append(ich.AdminEditUserDialog());

    if (this.model) {
      var nameInput = this.$('input[name=name]');
      nameInput.attr('disabled', true);
      nameInput.val(this.model.name);
      this.$('input[name=is_admin]').attr('checked', this.model.is_admin);
    }

    return this;
  },

  show: function () {
    var self = this;
    this.dialog = bootbox.dialog(this.render().el,
      [
        {
          "label": this.model ? 'Save User' : 'Add User',
          "class": "btn-primary",
          callback: function () { return self.onSubmit(); }
        },
        {
          "label": "Cancel",
          "class": "btn"
        }
      ],
      {
        header: this.model ? 'Edit User' : 'Add User',
        animate: false,
        backdrop: "static"
      }
    );
    if (this.model) {
      this.dialog.find('input[name=password]').focus(); 
    } else {
      this.dialog.find('input[name=name]').focus(); 
    }
  },

  onSubmit: function () {
    var form = $(this.dialog.find('form'));

    if (!this.model) {
      var valid = _.reduce(form.find('input[type=text],input[type=password]'), function (valid, input) {
        input = $(input);
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
    }

    var data = {
      name: $('input[name=name]', form).val(),
      password: $('input[name=password]', form).val(),
      is_admin: $('input[name=is_admin]', form).attr('checked') == 'checked'
    };

    var self = this;

    if (this.model) {
      $.ajax('/admin/users/' + this.model.id, { type: 'PUT', data: data })
        .success(function(data) {
          self.dialog.modal('hide');
          app.trigger('users-changed');
        })
        .error(function(res) {
          alert(res.responseText);
       });
    } else {
      $.post('/admin/users', data, function(data) {
        self.dialog.modal('hide');
        app.trigger('users-changed');
      })
      .error(function(res) {
        alert(res.responseText);
     });
    }

    return false;
  }
});
