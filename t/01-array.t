#!perl -w
use strict;
use Test::More tests => 8;

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

# create a nested object
sub genObj {
    my ($repl,$val) = @_;
    my $rn = $repl->repl;
    my $obj = MozRepl::RemoteObject->expr(<<JS)
(function(repl, val) {
    return { bar: [ 'baz', { value: val } ] };
})($rn, "$val")
JS
}

my $foo = genObj($repl, 'deep');
isa_ok $foo, 'MozRepl::RemoteObject';

my $bar = $foo->{bar};
isa_ok $bar, 'MozRepl::RemoteObject';

my @elements = @{ $bar };
is 0+@elements, 2, 'We have two elements';

#diag $_ for @$bar;

my $baz = $bar->[0];
is $baz, 'baz', 'First array element retrieved';

my $val = $bar->[1];
isa_ok $val, 'MozRepl::RemoteObject', 'Object retrieval from array';
is $val->{value}, 'deep', '... and the object contains our value';

push @{ $bar }, '"asdf"';
is 0+@{ $bar }, 3, '... even pushing an element works';
is $bar->[-1], 'asdf', '... and the value is actually stored';