#!perl -w
use strict;
use Test::More tests => 1;

use MozRepl::RemoteObject;
use MozRepl::AnyEvent;

my $repl = MozRepl::AnyEvent->new();
$repl->setup();

ok "We survived";