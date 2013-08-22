var Util = {
  bindMessageHandlers: function (obj) {
    if (obj.messageHandlers) {
      _.each(_.functions(obj.messageHandlers), function (name) {
        this.messageHandlers[name] = _.bind(this.messageHandlers[name], this);
      }, obj); 
    }
  },
  
  explodeDateTime: function (t) {
    return {
      date: t.getDate(),
      day: t.getDay(),
      month: t.getMonth(),
      year: t.getFullYear(),
      hours: this.pad2(t.getHours()),
      minutes: this.pad2(t.getMinutes()),
      seconds: this.pad2(t.getSeconds())
    }
  },
  
  pad2: function (number) {
    return (number < 10 ? '0' : '') + number
  }
};

jQuery.fn.serializeObject = function() {
  var arrayData, objectData;
  arrayData = this.serializeArray();
  objectData = {};

  $.each(arrayData, function() {
    var value;

    if (this.value != null) {
      value = this.value;
    } else {
      value = '';
    }

    if (objectData[this.name] != null) {
      if (!objectData[this.name].push) {
        objectData[this.name] = [objectData[this.name]];
      }

      objectData[this.name].push(value);
    } else {
      objectData[this.name] = value;
    }
  });

  return objectData;
};

jQuery.fn.appendSorted = function(el) {
  this.append(el);
  var members = this.children().sort(function(a,b) { return a.textContent.localeCompare(b.textContent) });
  this.empty().append(members);
}