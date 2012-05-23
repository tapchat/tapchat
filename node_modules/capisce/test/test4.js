"use strict";

var capisce = require('../lib/capisce.js');

var queue = new capisce.WorkingQueue(1); // Basically, a sequence

queue.perform(function(over) {
    console.log("Waiting 5 seconds...");
    over();
}).wait(5000).then(function(over) {
    console.log("done !");
    over();
});

var queue2 = new capisce.WorkingQueue(16);

queue2.perform(function(over) {
	console.log("First job done");
	over();
}).wait(5000, function(over) {
	console.log("Second job started after 5 seconds");
	over();
});