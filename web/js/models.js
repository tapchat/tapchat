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

  messageHandlers: {
    buffer_init: function () {
      // FIXME:
      if (!this.network.isBacklog) {
        console.info('activate?! ' + this.get('name') );
        this.trigger('activate');
      }
    }
  }
});

var ChatBuffer = Buffer.extend({
  messageHandlers: _.extend(Buffer.prototype.messageHandlers, {
    buffer_hidden: function (message) {
    }
  }),
});

var ChannelBuffer = ChatBuffer.extend({
  initialize: function () {
    ChatBuffer.prototype.initialize.call(this);
    this.memberList = new MemberList();
  },

  messageHandlers: _.extend(ChatBuffer.prototype.messageHandlers, {
    joined_channel: function (message) {
      if (!this.network.isBacklog)
        this.memberList.add(message);
    },

    parted_channel: function (message) {
      if (!this.network.isBacklog) {
        var member = this.memberList.findByNick(message.nick);
        this.memberList.remove(member);
      }
    },

    quit: function (message) {
      if (!this.network.isBacklog) {
        var member = this.memberList.findByNick(message.nick);
        this.memberList.remove(member);
      }
    },

    nickchange: function (message) {
      if (!this.network.isBacklog) {
        var member = this.memberList.findByNick(message.nick);
        member.set({ nick: message.newnick });
      }
    },

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
    },

    user_channel_mode: function (message) {
      if (!this.network.isBacklog) {
        var member = this.memberList.findByNick(message.nick);
        member.updateMode(message);
      }
    },

    channel_topic: function (message) {
      this.set('topic_text', message.topic);
      this.set('topic_by', message.author);
    }
  }),
});

var ConversationBuffer = ChatBuffer.extend({
  initialize: function () {
    ChatBuffer.prototype.initialize.call(this);
  },
  messageHandlers: _.extend(ChatBuffer.prototype.messageHandlers, {
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
  },

  messageHandlers: _.extend(Buffer.prototype.messageHandlers, {
    connecting: function (message) {
    },
    connected: function (message) {
    },
    connecting_finished: function (message) {
    },
    joining: function (message) {
    },
    user_mode: function (message) {
    },
    myinfo: function (message) {
      // FIXME: Do anything with this?
      this.network.myinfo = message;
    }
  })
});

var Network = Backbone.Model.extend({
  initialize: function () {
    this.isBacklog = true;
    this.bufferList = new BufferList();
  },

  processMessage: function (message) {
    var type = message.type;
    if (this.messageHandlers[type]) {
      this.messageHandlers[message.type].apply(this, [ message ]);
    }

    if (message.bid) {
      var buffer = this.bufferList.get(message.bid);
      if (buffer) {
        buffer.processMessage(message);
      }
    }
  },

  messageHandlers: {
    makebuffer: function (message) {
      var buffer = null;

      message.id = message.bid;
      switch (message.buffer_type) {
        case 'channel':
          buffer = new ChannelBuffer(message);
          break;
        case 'conversation':
          buffer = new ConversationBuffer(message)
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
  }
});

var Member = Backbone.Model.extend({
});
