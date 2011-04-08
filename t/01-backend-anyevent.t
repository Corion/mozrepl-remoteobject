#!perl -w
use strict;
use Test::More tests => 2;

use MozRepl::AnyEvent;

my $repl = MozRepl::AnyEvent->new();
$repl->setup();

ok "We survived";

like $repl->execute('1+1'), qr/^2\s*$/, "We can synchronously eval";