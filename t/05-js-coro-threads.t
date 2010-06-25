#!perl -w
use strict;
use Test::More;
use MozRepl::RemoteObject;

my $repl;
my $ok = eval {
    $repl = MozRepl::RemoteObject->install_bridge(
        #log => ['debug'] 
    );
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to MozRepl: $@";
} else {
    plan tests => 1;
};

my $Threads = do { local $/; open my $fh, '<', 't/Threads.js'; <$fh> };
$repl->expr($Threads);

$repl->expr(<<'JS');
    var receivedCallbacks = [];
    spawn( function() {
            // this thread runs for the lifetime of the bridge session
            while (true) {
                    // wait for all running threads to end
                    while (activeThreads.length) {
                            // show that we're active
                            // div.innerHTML = "thread manager: active";			
                            yield activeThreads.shift().join();
                    }

                    // show that we're idle
                    // div.innerHTML = "thread manager: idle";

                    // launch a thread if one is waiting
                    if (waitingThreads.length) {
                            var thread = waitingThreads.shift();
                            activeThreads.push(thread);
                            thread.start();
                    }

                    // wait for new threads if necessary
                    while (!activeThreads.length && !waitingThreads.length) {
                            yield sleep(100);
                    }
            }
    });
JS