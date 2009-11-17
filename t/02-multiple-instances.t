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
    plan tests => 1;
};

my $second;
$ok = eval {
    $second = MozRepl::RemoteObject->install_bridge();
    1;
};
ok $ok, "We can create a second bridge instance";
