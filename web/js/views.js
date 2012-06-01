var BUFFER_EVENTS = {
  "socked_closed":         "Disconnected",
  "connecting":            "Connecting",
  "quit_server":           "Quit server",
  "notice":                "{{msg}}",
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
  "channel_topic":         "{{nick}} set the topic: {{topic}}",
  "channel_topic_cleared": "{{nick}} cleared the topic",
  "channel_mode":          "Channel mode: {{diff}} by {{from}}"
};

var AppView = Backbone.View.extend({
  initialize: function (options) {
    _.bindAll(this, 'addNetwork', 'removeNetwork');
    window.app.networkList.bind('add', this.addNetwork);
    window.app.networkList.bind('remove', this.removeNetwork);
  },
  
  addNetwork: function (network) {
    var view = new NetworkListRowView({ model: network });
    $('#networks').append(view.render().el);
  },
  
  removeNetwork: function (network) {
    network.view.remove();
  }
});

var NetworkListRowView = Backbone.View.extend({
  tagName: 'li',
  
  initialize: function () {
    _.bindAll(this, 'addBuffer', 'removeBuffer', 'render');
    this.model.bind('change', this.render);
    this.model.view = this;
    
    $(this.el).html(ich.NetworkListRowView());

    this.render();
    
    this.model.bufferList.bind('add', this.addBuffer);
    this.model.bufferList.bind('remove', this.removeBuffer);
  },
    
  addBuffer: function (buffer) {
    // FIXME: Not really sure where to put all this.
    view = new BufferView({ model: buffer });
    $('#buffers').append(view.el);
    
    // 'console' buffers are a special case
    if (buffer.get('name') == '*') {
      return;
    }
    
    var view = new BufferListRowView({ model: buffer });
    this.$('.bufferList').append(view.render().el);
    
    if (buffer.get('buffer_type') == 'channel') {
      view = new MemberListView({ model: buffer });
      $('#users').append(view.render().el);
    }
  },
  
  removeBuffer: function (buffer) {
    buffer.listRowView.remove();
  },
  
  select: function () {
    $('#networks li').removeClass('active');
    $(this.el).addClass('active');
  },
  
  render: function () {
    var data = this.model.toJSON();
    data.url = '#' + this.model.id;
    this.$('.networkInfo').html(ich.NetworkListRowInfoView(data));
    return this;
  }
});

var BufferListRowView = Backbone.View.extend({
  tagName: 'li',
  
  initialize: function () {
    _.bindAll(this, 'render', 'hide');
    this.model.bind('change', this.render);
    this.model.bind('hidden', this.hide);
    this.model.listRowView = this;
    
    if (this.model.get('hidden') == true) {
      $(this.el).addClass('archived');
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
    var data = this.model.toJSON();

    var network = app.networkList.get(this.model.get('nid'));
    data.url = '#' + network.id + '/' + this.model.id;
    
    $(this.el).html(ich.BufferListRowView(data));
    return this;
  }
});

var MemberListView = Backbone.View.extend({
  tagName: 'ul',
  
  initialize: function () {
    // FIXME: Is it OK to have '#' in ID?
    this.el.id = 'users-' + this.model.get('name');
    
    _.bindAll(this, 'addMember', 'removeMember');
    
    this.model.memberListView = this;
    this.model.memberList.bind('add', this.addMember);
    this.model.memberList.bind('remove', this.removeMember);
  },
  
  show: function () {
    $('#users ul').removeClass('active');
    $(this.el).addClass('active');
  },
  
  addMember: function (member) {
    var view = new MemberListRowView({ model: member });
    $(this.el).append(view.render().el);
  },
  
  removeMember: function (member) {
    member.view.remove();
  }
});

var MemberListRowView = Backbone.View.extend({
  tagName: 'li',
  
  initialize: function () {
    _.bindAll(this, 'render');
    this.model.bind('change', this.render);
    this.model.view = this;
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
  className: 'buffer',

  initialize: function () {
    _.bindAll(this, 'addEvent');

    $(this.el).addClass('buffer');
    // FIXME: Is it OK to have '#' in ID?
    this.el.id = 'buffer-' + this.model.get('name');

    this.model.view = this;
    this.model.bind('event', this.addEvent);
  },

  show: function () {
    $('#buffers div').removeClass('active');
    $(this.el).addClass('active');
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
        msg:      text
      });
      $(rendered).find('a').linkify({
        handleLinks: function (links) {
          return links.prop('target', '_new');
        }
      })
      $(this.el).append(rendered);
    }
  }
});
