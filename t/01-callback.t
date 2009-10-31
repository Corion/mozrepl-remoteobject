#!perl -w
use strict;
use Test::More;

use MozRepl::RemoteObject;

my $repl;
my $ok = eval {
    $repl = MozRepl::RemoteObject->install_bridge(
        #log => ['debug'],
    );
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to MozRepl: $@";
} else {
    plan tests => 9;
};

sub genObj {
    my ($repl) = @_;
    my $rn = $repl->name;
    my $obj = $repl->expr(<<JS)
(function() {
    var res = {};
    res.foo = "bar";
    res.baz = "flirble";
    return res
})()
JS
}

my $obj = genObj($repl);
isa_ok $obj, 'MozRepl::RemoteObject::Instance';

my $called = 0;
my @events;
$obj->{oncommand} = sub {
    $called++;
    push @events, @_;
};
ok 1, "Stored callback";
my $cb = $obj->{oncommand};
isa_ok $obj->{oncommand},
    'MozRepl::RemoteObject::Instance',
    "We can store a subroutine as a callback";

$cb->('from_perl');
is $called, 1, "We got called back on a direct call from Perl";

my $trigger_command = $repl->declare(<<'JS');
    function(o,m) {
        o.oncommand(m);
    };
JS
$trigger_command->($obj,'from_js');
is $called, 2, "We got called indirectly by a callback in Javascript";
is_deeply \@events,
    ['from_perl','from_js'],
    "We received the events in the order we expected";

my $window = $repl->expr(<<'JS');
    repl._workContext.window
JS
isa_ok $window, 'MozRepl::RemoteObject::Instance',
    "We got a handle on window";

my $timer_id = $window->setTimeout($trigger_command, 2000, $obj, 'from_timer');
is_deeply \@events,
    ['from_perl','from_js'],
    "Delayed events don't trigger immediately";

sleep 3;
$repl->poll;

is_deeply \@events,
    ['from_perl','from_js', 'from_timer'],
    "Delayed triggers trigger eventually";