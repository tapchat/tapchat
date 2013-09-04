class BufferEvent extends Backbone.Model
  @MERGEABLE_TYPES = ['joined_channel', 'parted_channel', 'quit', 'nickchange']

  constructor: (firstItem) ->
    super({})
    @items = new BufferEventItemList()
    @items.add(firstItem)

    @items.bind 'add', =>
      @trigger('change')

  shouldMerge: (otherItem) ->
    _.contains(BufferEvent.MERGEABLE_TYPES, @items.first().get('type')) && \
    _.contains(BufferEvent.MERGEABLE_TYPES, otherItem.get('type')) && \
    @items.first().isSameDay(otherItem)

window.BufferEvent = BufferEvent