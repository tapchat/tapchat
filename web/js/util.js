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