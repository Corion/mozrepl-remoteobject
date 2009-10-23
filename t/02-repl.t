#!perl -w
use strict;
use Test::More tests => 2;

use MozRepl::RemoteObject;

my $repl = MozRepl->new;
$repl->setup({
    client => {
        extra_client_args => {
            binmode => 1,
        }
    },
    log => [qw/ error/],
    #log => [qw/ debug error/],
    plugins => { plugins => [qw[ Repl::Load ]] }, # I'm loading my own JSON serializer
});

diag "--- Loading object functionality into repl\n";
MozRepl::RemoteObject->install_bridge($repl);

my $id = MozRepl::RemoteObject->expr(<<JS);
function(v) { return v }
JS

my $JSrepl = $id->($repl);

isa_ok $JSrepl, 'MozRepl::RemoteObject', 'We can pass in a MozRepl object';

is $JSrepl->{_name}, $repl->repl, '... and get at the JS implementation';
