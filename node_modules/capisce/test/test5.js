"use strict";

var capisce = require('../lib/capisce.js');
var queue = new capisce.WorkingQueue(1);

function myJob(word1, word2, over) {
    console.log('' + word1 + ', ' + word2 + ' !');
    over();
}

queue.perform(myJob, 'Hello', 'world');
queue.perform(myJob, 'Howdy', 'pardner');
queue.wait(2000, myJob, 'At last', "it's over");

queue.whenDone(function() {
    console.log("done !");
});
