#!perl -w
use strict;
use Test::More tests => 2;

use MozRepl::RemoteObject;
my $repl = MozRepl->new;
$repl->setup({
    log => [qw/ error/],
    plugins => { plugins => [qw[ JSON2 ]] },
});
MozRepl::RemoteObject->install_bridge($repl);

my %object_count;

$object_count{ start } = scalar MozRepl::RemoteObject->__activeObjects;

my $obj = MozRepl::RemoteObject->expr(<<JS);
    return [1,2,3]
JS

isa_ok $obj, 'MozRepl::RemoteObject', 'Our object';

$object_count{ cleanup_start } = scalar MozRepl::RemoteObject->__activeObjects;

undef $obj;

$object_count{ cleanup_end } = scalar MozRepl::RemoteObject->__activeObjects;

is $object_count{ start }, $object_count{ cleanup_start }-1, 'At start, we have one less object than after retrieving one';

is $object_count{ cleanup_start }, $object_count{ cleanup_end }+1, 'Before cleanup, we had one more object';
is $object_count{ cleanup_end }, $object_count{ start }, 'No objects left over at the end of the program';
