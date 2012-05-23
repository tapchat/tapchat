"use strict";

var capisce = require('../lib/capisce.js');

function test2() {
    var res1, res2, res3=[];

    capisce.sequence().perform(function(over) {
        console.log("Starting res1");
        setTimeout(function() {
            console.log("Ended res1");
            res1 = "Hello";
            over();
        }, 1000);
    }).then(function(over) {
        console.log("Starting res2");
        setTimeout(function() {
            console.log("Ended res2");
            res2 = "World";
            over();
        }, 1000);
    }).then(function(concurrently, over) {
        var i;
        var count = 0;
        for(i=0;i<10;i++) {
            concurrently.perform(function(over) {
                var c = count++;
                console.log("Starting final job "+c);
                setTimeout(function() {
                    var text = res1+", "+res2+":"+c;
                    res3.push(text);
                    console.log(text);
                    over();
                }, Math.random()*2000);
            });
        }
        concurrently.whenDone(function() {
            console.log("Concurrently block done");
        });
        over();
    }, 4).then(function(over) {
        console.log("res3.length="+res3.length);
        console.log("All done !");
    });
}

test2();