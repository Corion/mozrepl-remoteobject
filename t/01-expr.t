#!perl -w
use strict;
use Test::More;

use MozRepl::RemoteObject;

my $repl;
my $ok = eval {
    $repl = MozRepl::RemoteObject->install_bridge();
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to MozRepl: $@";
} else {
    plan tests => 4;
};

my $four = MozRepl::RemoteObject->expr(<<JS);
    2+2
JS

is $four, 4, "Addition in Javascript works";

my $wrapped_repl = MozRepl::RemoteObject->expr(<<JS);
    repl
JS

my $repl_id = $wrapped_repl->__id;
my $identity = MozRepl::RemoteObject->expr(<<JS);
    repl === repl.getLink($repl_id)
JS

is $identity, 'true', "Object identity in Javascript works";

my $adder = MozRepl::RemoteObject->expr(<<JS);
    function(a,b) { return a+b }
JS
isa_ok $adder, 'MozRepl::RemoteObject';

my $five = $adder->(2,3);
is $five, 5, "Anonymous functions in Javascript work as well";

