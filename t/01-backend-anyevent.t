#!perl -w
use strict;
use Test::More;

my $ok = eval {
    require AnyEvent;
    1;
};
my $err = $@;

my $repl;

$ok and $ok = eval {
    require MozRepl::AnyEvent;
    $repl = MozRepl::AnyEvent->new();
    $repl->setup();
    1;
};
if (! $ok) {
    $err ||= $@;
    plan skip_all => "Couldn't connect to Firefox: $err";
} else {
    plan tests => 2;
};

ok "We survived";

like $repl->execute('1+1'), qr/^2\s*$/, "We can synchronously eval";