_.templateSettings = {
  interpolate : /\{\{(.+?)\}\}/g
};

$(function () {
  window.app = new App();
  window.app.view = new AppView({
    el: $('#app')
  });

  window.app.main_menu = new MainMenuView();

  window.app.settings = new SettingsView();
  $('#pages').append(window.app.settings.el);

  window.app.admin = new AdminView();
  $('#pages').append(window.app.admin.el);

  Backbone.history.start();

  var session = $.cookie('session');
  if (session) {
    app.connect();
  } else {
    app.view.showLoginDialog();
  }

  $('#settings-item').tappable(function () {
    app.controller.navigate('settings', { trigger: true });
  });

  $('#admin-item').tappable(function() {
    app.controller.navigate('admin', { trigger: true });
  });

  $('#settings-btn').tappable(function () {
    var currentPath = window.location.hash.substring(1);
    if (currentPath !== 'settings') {
      this.beforeSettings = currentPath;
      app.controller.navigate('settings', { trigger: true });
    } else {
      app.controller.navigate(this.beforeSettings, { trigger: true });
      this.beforeSettings = null;
    }
  });

  $('#join-btn').tappable(function () {
    new JoinChannelDialog().show();
  });

  $('#members-btn').tappable(function () {
    $('#sidebar').toggleClass('show');
  });

  $('#logout-btn').tappable(function () {
    $.post('/chat/logout', null, function (data) {
      $.cookie('session', null);
      app.view.showLoginDialog();
    })
    .error(function() {
      alert('error');
    });
  });

  new ScrollFix($('#networks')[0]);
  new ScrollFix($('#users')[0]);

  // From http://24ways.org/2011/raising-the-bar-on-mobile
  // FIXME: Everything below here is a big mess.

  var getScrollTop = function() {
    return window.pageYOffset ||
      document.compatMode === 'CSS1Compat' && document.documentElement.scrollTop ||
      document.body.scrollTop ||
      0;
  };

  var scrollTop = function() {
    if (!supportOrientation)
      return;

    document.body.style.height = screen.height + 'px';

    setTimeout(function(){
      window.scrollTo(0, 1);
      window.scrollTo(0, getScrollTop() === 1 ? 0 : 1);
      var pageHeight = window.innerHeight + 'px';
      document.body.style.height = pageHeight;
    }, 1);
 };

  var supportOrientation = typeof window.orientation != 'undefined';
  if (supportOrientation) {
    window.onorientationchange = scrollTop;
    scrollTop();
  }

  $('#entry input').bind('focus', function() {
    var pageHeight = window.innerHeight + 'px';
    window.scrollTo(0, 1);
    setTimeout(function() {
      document.body.style.height = pageHeight;
    },1);
  });
  return $('#entry input').bind('blur', function() {
    setTimeout(function() {
      return scrollTop();
    },1);
  });
});
