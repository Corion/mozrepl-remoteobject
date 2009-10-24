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
    plan tests => 2;
};

diag "--- Loading object functionality into repl\n";
MozRepl::RemoteObject->install_bridge($repl);

my $id = MozRepl::RemoteObject->expr(<<JS);
function(v) { return v }
JS

my $JSrepl = $id->($repl);

isa_ok $JSrepl, 'MozRepl::RemoteObject', 'We can pass in a MozRepl object';

is $JSrepl->{_name}, $repl->repl, '... and get at the JS implementation';
