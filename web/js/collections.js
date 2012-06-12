var NetworkList = Backbone.Collection.extend({
  model: Network
});

var BufferList = Backbone.Collection.extend({
  model: Buffer,

  findByName: function (name) {
    return this.find(function (buffer) {
      return buffer.get('name') == name;
    });
  }
});

var MemberList = Backbone.Collection.extend({
  model: Member,

  findByNick: function (nick) {
    return this.find(function (member) {
      return member.get('nick') == nick;
    });
  }
});
