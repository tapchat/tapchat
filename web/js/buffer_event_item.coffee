class BufferEventItem extends Backbone.Model
  constructor: (attrs) ->
    super
    
  isSameDay: (otherItem) ->
    d1 = new Date(@get('time') * 1000)
    d2 = new Date(otherItem.get('time') * 1000)
    return d1.getYear() == d2.getYear() and \
      d1.getMonth() == d2.getMonth() and \
      d1.getDate() == d2.getDate()

window.BufferEventItem = BufferEventItem