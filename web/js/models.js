// rename to 'Me' or 'MyInfo'
var User = Backbone.Model.extend({
});

var Buffer = Backbone.Model.extend({
  messageIds: {},

  processMessage: function (message) {
    var eid  = message.eid;
    var type = message.type;

    if (eid > -1) {
      if (this.messageIds[eid]) {
        return;
      }
      this.messageIds[eid] = eid;
    }

    this.trigger('event', message);

    if (this.messageHandlers[type]) {
      this.messageHandlers[message.type].apply(this, [ message ]);
    }
  },

  markRead: function(eid) {
    // FIXME: Implement this.
    console.log('Mark read ' + eid);
  },

  messageHandlers: {},

  nonBacklogMessageHandlers: {
    buffer_hidden: function (message) {
      this.set('hidden', true);
    },
    buffer_unhidden: function (message) {
      this.set('hidden', false);
    }
  }
});

var ChannelBuffer = Buffer.extend({
  initialize: function () {
    Buffer.prototype.initialize.call(this);
    this.memberList = new MemberList();
  },

  messageHandlers: _.extend(Buffer.prototype.messageHandlers, {
    channel_init: function (message) {
      this.set(message.topic);

      _.each(message.members, _.bind(function (member) {
        var existingMember = this.memberList.findByNick(member.nick);
        if (existingMember) {
          existingMember.set(member);
        } else {
          this.memberList.add(member);
        }
      }, this));
    }
  }),

  nonBacklogMessageHandlers: _.extend(Buffer.prototype.nonBacklogMessageHandlers, {
    channel_topic: function (message) {
      this.set('topic_text', message.topic);
      this.set('topic_by', message.author);
    },

    user_channel_mode: function (message) {
      var member = this.memberList.findByNick(message.nick);
      member.updateMode(message);
    },

    joined_channel: function (message) {
      this.memberList.add(message);
    },

    parted_channel: function (message) {
      var member = this.memberList.findByNick(message.nick);
      this.memberList.remove(member);
      member.destroy();
    },

    quit: function (message) {
      var member = this.memberList.findByNick(message.nick);
      this.memberList.remove(member);
      member.destroy();
    },

    kicked_channel: function (message) {
      var member = this.memberList.findByNick(message.nick);
      this.memberList.remove(member);
      member.destroy();
    },

    you_joined_channel: function (message) {
      this.set('joined', true);
    },

    you_parted_channel: function (message) {
      this.set('joined', false);
    },

    nickchange: function (message) {
      this.updateMemberNick(message);
    },

    you_nickchange: function (message) {
      this.updateMemberNick(message);
    }
  }),

  updateMemberNick: function (message) {
    var member = this.memberList.findByNick(message.oldnick);
    member.set({ nick: message.newnick });
  }
});

var ConversationBuffer = Buffer.extend({
  initialize: function () {
    Buffer.prototype.initialize.call(this);
  },
  messageHandlers: _.extend(Buffer.prototype.messageHandlers, {
    whois_response: function (message) {
      if (!this.network.isBacklog) {
        console.info('FIXME');
        this.trigger('whois_response', message);
      }
    }
  })
});

var ConsoleBuffer = Buffer.extend({
  initialize: function () {
    Buffer.prototype.initialize.call(this);
  }
});

var Network = Backbone.Model.extend({
  initialize: function (attributes) {
    this.isBacklog  = (app.connectionState !== 'loaded');
    this.bufferList = new BufferList();
    this.update(attributes);
  },

  reconnect: function () {
    app.send({
      _method: 'reconnect',
      cid:     this.id
    });
  },

  disconnect: function () {
    app.send({
      _method: 'disconnect',
      cid:     this.id
    });
  },

  deleteConnection: function () {
    app.send({
      _method: 'delete-connection',
      cid:     this.id
    });
  },

  join: function (channel) {
    app.send({
      _method: 'join',
      cid:     this.id,
      channel: channel
    });
  },

  getConsoleBuffer: function () {
    return this.bufferList.find(function (buffer) {
      return (buffer instanceof ConsoleBuffer);
    });
  },

  processMessage: function (message) {
    var type = message.type;

    if (this.messageHandlers[type]) {
      this.messageHandlers[message.type].apply(this, [ message ]);
    }

    if (!message.is_backlog && !this.isBacklog && this.nonBacklogMessageHandlers[type]) {
      this.nonBacklogMessageHandlers[type].apply(this, [ message ]);
    }

    if (message.bid) {
      var buffer = this.bufferList.get(message.bid);
      if (buffer) {
        buffer.processMessage(message);
      }
    }
  },

  processResponse: function (response) {
    if (response.type === 'open_buffer') {
      var buffer = this.bufferList.findByName(response.name);
      if (buffer) {
        app.showBuffer(buffer.network.id, buffer.id);
        this.pendingOpenBuffer = null;
      } else {
        this.pendingOpenBuffer = response.name;
      }
    }
  },

  reload: function (message) {
    this.update(message);
  },

  update: function (message) {
    console.log('update!', message);
    if (this.get('disconnected')) {
      this.set('state', 'disconnected');
    } else {
      this.set('state', 'connected');
    }
  },

  messageHandlers: {
    makebuffer: function (message) {
      message.id = message.bid;

      var buffer = this.bufferList.get(message.bid);
      if (buffer) {
        buffer.reload(message);
        return;
      }

      switch (message.buffer_type) {
        case 'channel':
          buffer = new ChannelBuffer(message);
          break;
        case 'conversation':
          buffer = new ConversationBuffer(message);
          break;
        case 'console':
          buffer = new ConsoleBuffer(message);
          break;
        default:
          throw 'Unknown buffer type: ' + message.buffer_type;
      }

      buffer.network = this;
      this.bufferList.add(buffer);
    },

    end_of_backlog: function (message) {
      this.isBacklog = false;
    }
  },

  nonBacklogMessageHandlers: {
    server_details_changed: function (message) {
      this.update(message);
    },

    myinfo: function (message) {
      // FIXME: Do anything with this?
      this.network.myinfo = message;
    },

    you_nickchange: function (message) {
      this.set('nick', message.newnick);
    },

    connecting: function (message) {
      this.set('nick', message.nick);
      this.set('state', 'connecting');
    },

    connecting_retry: function (message) {
      this.set('state', 'retrying');
    },

    waiting_to_retry: function (message) {
      this.set('state', 'retrying');
    },

    connecting_cancelled: function (message) {
      this.set('state', 'disconnected');
    },

    connecting_failed: function (message) {
      this.set('state', 'disconnected');
    },

    connected: function (message) {
      // not used
    },

    connecting_finished: function (message) {
      this.set('state', 'connected');
    },

    socket_closed: function (message) {
      this.set('state', 'disconnected');
    },

    delete_buffer: function (message) {
      var buffer = this.bufferList.get(message.bid);
      this.bufferList.remove(buffer);
      buffer.destroy();
    }
  }
});

var Member = Backbone.Model.extend({
});
