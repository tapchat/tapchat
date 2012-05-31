var NetworkList = Backbone.Collection.extend({
  model: Network
});

var BufferList = Backbone.Collection.extend({
  model: Buffer
});

var MemberList = Backbone.Collection.extend({
  model: Member,
  
  findByNick: function (nick) { 
    return this.find(function (member) {
      return member.get('nick') == nick;
    });
  }
});
