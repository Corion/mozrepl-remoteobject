#!perl -w
use strict;
use Test::More;

use MozRepl::RemoteObject;

my $repl;
my $ok = eval {
    $repl = MozRepl::RemoteObject->install_bridge(
        log => ['debug'],
    );
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to MozRepl: $@";
} else {
    plan tests => 4;
};

sub genObj {
    my ($repl) = @_;
    my $obj = $repl->expr(<<'JS')
    { foo: "bar", baz: "flirble" }
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
my $cb = $obj->{oncommand};
isa_ok $obj->{oncommand},
    'MozRepl::RemoteObject::Instance',
    "We can store a subroutine as a callback";

$cb->('from_perl');
is $called, 1, "We got called back on a direct call from Perl";

my $trigger_command = $repl->declare(<<'JS');
    function(o) {
        o.oncommand('from_js');
    };
JS
$trigger_command->($obj);
is $called, 2, "We got called indirectly by a callback in Javascript";

is_deeply \@events, ['from_perl','from_js'], "We received the events in the order we expected";