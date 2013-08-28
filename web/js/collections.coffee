class ConnectionList extends Backbone.Collection
  model: Connection

class BufferList extends Backbone.Collection
  model: Buffer

  findByName: (name) ->
    @find (buffer) -> buffer.get('name') == name

class MemberList extends Backbone.Collection
  findByNick: (nick) ->
    @find (member) -> member.get('nick') == nick

  removeByNick: (nick) ->
    if member = @findByNick(nick)
      @remove(member)

  updateNick: (message) ->
    if member = @findByNick(message.nick)
      member.update(message)

class BufferEventList extends Backbone.Collection
  model: BufferEvent

class BufferEventItemList extends Backbone.Collection
  model: BufferEventItem

window.ConnectionList = ConnectionList
window.BufferList = BufferList
window.MemberList = MemberList
window.BufferEventList = BufferEventList
window.BufferEventItemList = BufferEventItemList