#!perl -w
use strict;
use Test::More tests => 2;

use MozRepl::AnyEvent;

my $repl = MozRepl::AnyEvent->new();

my $ok = eval {
    $repl->setup();
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to Firefix: $@";
} else {
    plan tests => 2;
};

ok "We survived";

like $repl->execute('1+1'), qr/^2\s*$/, "We can synchronously eval";