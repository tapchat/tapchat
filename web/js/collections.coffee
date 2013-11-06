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
      member.stopListening()
      member.destroy()

  updateNick: (message) ->
    if member = @findByNick(message.oldnick)
      member.set('nick', message.newnick)

class BufferEventList extends Backbone.Collection
  model: BufferEvent
  constructor: () ->
    super
    @minEid = -1
    @bind 'add', (event) =>
      eid = event.items.first().get('eid')
      if @minEid < 0
        @minEid = eid
      else
        @minEid = Math.min(@minEid, eid)

class BufferEventItemList extends Backbone.Collection
  model: BufferEventItem

window.ConnectionList = ConnectionList
window.BufferList = BufferList
window.MemberList = MemberList
window.BufferEventList = BufferEventList
window.BufferEventItemList = BufferEventItemList