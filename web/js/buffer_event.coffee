class BufferEvent extends Backbone.Model
  MERGEABLE_TYPES = ['joined_channel', 'parted_channel', 'quit', 'nickchange']

  constructor: (firstItem) ->
    super({})
    @items = new BufferEventItemList()
    @items.add(firstItem)

  shouldMerge: (otherItem) ->
    _.contains(MERGEABLE_TYPES, @items.first().get('type')) && \
    _.contains(MERGEABLE_TYPES, otherItem.get('type')) && \
    @items.first().isSameDay(otherItem)

window.BufferEvent = BufferEvent