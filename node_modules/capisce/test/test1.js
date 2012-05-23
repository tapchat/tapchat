"use strict";

var capisce = require('../lib/capisce.js');

function test1() {
    var q = new capisce.CollectingWorkingQueue(16);
    
    q.whenDone(function(result) {
        console.log("Done !");
        console.log("result.length="+result.length);
        result.sort();
        console.log("result[0]="+result[0]);
        console.log("result[result.length-1]="+result[result.length-1]);
    });

    var count = 0;
    for(var i=0;i<1000;i++) {
        q.perform(function(over) {
            var id = count++;
            var duration = Math.random()*100;
            console.log("Starting "+id+"... ");
            setTimeout(function() {
                console.log("... over "+id+", duration="+duration+"ms");
                over(null, "result-"+id);
            }, duration);
        });
    }

    q.doneAddingJobs();
}

test1();