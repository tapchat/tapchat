Backbone.sync = ->

_.templateSettings =
  interpolate : /\{\{(.+?)\}\}/g

window.app = {}

$ ->
  window.app.controller = new Router()
  window.app.client = new TapchatClient()
  window.app.view = new AppView({el: $('#app')})

  window.app.main_menu = new MainMenuView()

  window.app.settings = new SettingsView()
  $('#pages').append(window.app.settings.el)

  window.app.admin = new AdminView()
  $('#pages').append(window.app.admin.el)

  $("#settings-item").tappable ->
    app.controller.navigate "settings",
      trigger: true

  $("#admin-item").tappable ->
    app.controller.navigate "admin",
      trigger: true

  $("#settings-btn").tappable ->
    currentPath = window.location.hash.substring(1)
    if currentPath isnt "settings"
      @beforeSettings = currentPath
      app.controller.navigate "settings",
        trigger: true

    else
      app.controller.navigate @beforeSettings,
        trigger: true

      @beforeSettings = null

  $("#join-btn").tappable ->
    new JoinChannelDialog().show()

  $("#members-btn").tappable ->
    $("#sidebar").toggleClass "show"

  $("#logout-btn").tappable ->
    $.post("/chat/logout", null, (data) ->
      $.cookie "session", null
      app.view.showLoginDialog()
    ).error ->
      alert "error"

  new ScrollFix($("#networks")[0])
  new ScrollFix($("#users")[0])

  Backbone.history.start()

  session = $.cookie('session')
  if session
    app.client.connect()
  else
    app.view.showLoginDialog()

  # From http://24ways.org/2011/raising-the-bar-on-mobile
  # FIXME: Everything below here is a big mess.
  getScrollTop = ->
    window.pageYOffset or \
    document.compatMode is "CSS1Compat" and \
    document.documentElement.scrollTop or \
    document.body.scrollTop or 0

  scrollTop = ->
    return  unless supportOrientation
    document.body.style.height = screen.height + "px"
    setTimeout (->
      window.scrollTo 0, 1
      window.scrollTo 0, (if getScrollTop() is 1 then 0 else 1)
      pageHeight = window.innerHeight + "px"
      document.body.style.height = pageHeight
    ), 1

  supportOrientation = typeof window.orientation isnt "undefined"
  if supportOrientation
    window.onorientationchange = scrollTop
    scrollTop()
  $("#entry input").bind "focus", ->
    pageHeight = window.innerHeight + "px"
    window.scrollTo 0, 1
    setTimeout (->
      document.body.style.height = pageHeight
    ), 1

  $("#entry input").bind "blur", ->
    setTimeout (->
      scrollTop()
    ), 1

