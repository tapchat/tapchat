"use strict";

var capisce = require('../lib/capisce.js');

function test(hold, over) {
    var queue; 
    var ok = false;

    capisce.sequence().perform(function(over) {
        queue = new capisce.WorkingQueue();
        if(hold) queue.hold();
        over();
    }).then(function(concurrently, over) {
        var i;
        for(i=0;i<10;i++) {
            concurrently.perform(function(over) {
                setTimeout(function() {
                    queue.perform(function(over) {
                        if(!ok) throw 'The queue was not held !';
                        console.log("Hello, world");
                        over();
                    });
                    over();
                }, Math.random() * 1000);
            });
        }
        over();
    }).then(function(over) {
        ok = true;
        queue.go();
        queue.whenDone(function() {
            over();
        });
    }).then(function(over) {
        console.log("All done !");
        over();
    }).whenDone(function() {
        over();
    });
}

capisce.sequence().perform(function(over) {
    console.log("First pass should succeed");
    test(true, over);
}).then(function(over) {
    console.log("Second pass should fail miserably");
    test(false, over);
});