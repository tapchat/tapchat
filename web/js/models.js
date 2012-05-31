// rename to 'Me' or 'MyInf'
var User = Backbone.Model.extend({  
});

var Buffer = Backbone.Model.extend({  
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

var ChatBuffer = Backbone.Model.extend({
  messageHandlers: _.extend(Buffer.prototype.messageHandlers, {    
    buffer_msg: function (message) {
      this.trigger('line', message);
    },

    buffer_me_msg: function (message) {
      this.trigger('line', message);
    },
    
    buffer_hidden: function (message) {
      this.trigger('hidden');
    }
  }),
});

var ChannelBuffer = ChatBuffer.extend({
  initialize: function () {
    ChatBuffer.prototype.initialize.call(this);
    this.memberList = new MemberList();
  },

  messageHandlers: _.extend(ChatBuffer.prototype.messageHandlers, {
    you_joined_channel: function (message) {
      this.trigger('text_line', 'You have joined');
    },

    channel_mode_is: function (message) {
      this.trigger('text_line', 'Mode is: ' + message.newmode);
    },
    
    channel_timestamp: function (message) {
      this.trigger('text_line', 'Created at: ' + message.timestamp);
    },
    
    joined_channel: function (message) {
      //this.trigger('line', message.nick + ' has joined');
      this.trigger('line', message);

      if (!this.network.isBacklog)
        this.memberList.add(message);
    },
    
    parted_channel: function (message) {
      //this.trigger('line', message.nick + ' has left');
      this.trigger('line', message);
      
      if (!this.network.isBacklog) {
        var member = this.memberList.findByNick(message.nick);
        this.memberList.remove(member);
      }
    },
    
    quit: function (message) {
      //this.trigger('line', message.nick + ' has quit');
      this.trigger('line', message);
      
      if (!this.network.isBacklog) {        
        var member = this.memberList.findByNick(message.nick);
        this.memberList.remove(member);
      }
    },
    
    nickchange: function (message) {
      this.trigger('text_line', message.oldnick + ' is now known as ' + message.newnick);

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
      this.trigger('text_line', '*** Mode ' + message.diff + ' ' + message.nick + ' by ' + message.from);
      if (!this.network.isBacklog) {
        var member = this.memberList.findByNick(message.nick);
        member.updateMode(message);
      }
    },

    channel_topic: function (message) {
      this.set('topic', message.topic);
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
    
    // Treating all these the same, for now at least.
    var statusMessages = [ 
      'notice', 'server_welcome', 'server_yourhost', 'server_created',
      'server_myinfo', 'server_luserclient', 'server_luserop', 'server_luserme',
      'server_n_local', 'server_n_global', 'server_motdstart', 'server_motd', 
      'server_endofmotd'
    ];
    _.each(statusMessages, _.bind(function (name) {
      this.messageHandlers[name] = function (message) {
        this.trigger('text_line', message.msg);
      }
    }, this));
    
    var valueMessages = [
      'server_luserop', 'server_luserchannels'
    ];
    _.each(valueMessages, _.bind(function (name) {
      this.messageHandlers[name] = function (message) {
        this.trigger('text_line', message.msg + ': ' + message.value);
      }
    }, this));
  },
  
  messageHandlers: _.extend(Buffer.prototype.messageHandlers, {
    connecting: function (message) {
      this.trigger('text_line', 'Connecting to ' + message.hostname);
    },
    connected: function (message) {
      this.trigger('text_line', 'Connected to ' + message.hostname);
    },
    connecting_finished: function (message) {
      // FIXME: Do anything?
    },
    joining: function (message) {
      this.trigger('text_line', 'Joining ' + message.channels.join(', ') + '...');
    },
    user_mode: function (message) {
      this.trigger('text_line', 'Your mode is: +' + message.newmode);
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
