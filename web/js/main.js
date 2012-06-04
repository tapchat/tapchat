_.templateSettings = {
  interpolate : /\{\{(.+?)\}\}/g
};

var UI = {
  showLoginDialog: function () {
    var content = $('#login');
    content.removeClass('hide');
    var dialog = bootbox.dialog(content, {
      "label" : "Login",
      "class" : "btn-primary",
      "callback": function() {
          var password = dialog.find("input[type=password]").val()
          if (password.length == 0) {
            return false;
          }
          app.connect(password);
          return true;
      }
    }, {
      "animate": false,
      "backdrop": "static"
    });

    dialog.find('form').on('submit', function (e) {
      e.preventDefault();
      dialog.find(".btn-primary").click();
    });

    dialog.find("input[type=password]").focus();
  },

  sendMessage: function (text) {
    if (text == "") return;

    // FIXME
    var network = window.app.controller.current_network;
    var buffer  = window.app.controller.current_buffer;

    var msg = {
          cid: network.get('nid'),
           to: buffer.get('name'),
          msg: text,
       _reqid: window.app._reqid,
      _method: "say"
    };
    window.app.send(msg);
  }
};

$(function () {
  window.app = new App();
  window.app.view = new AppView({
    el: $('#app')
  });

  Backbone.history.start();

  $('#entry input').keypress(function(event) {
    if (event.keyCode == 13) {
      var text = $(this).val();
      $(this).val('');
      UI.sendMessage(text);
    }
  });

  // FIXME
  var password = null;
  if (password) {
    app.connect(password);
  } else {
    UI.showLoginDialog();
  }

  $('.tappable').tappable(function () {
    $('#sidebar').toggleClass('show');
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
