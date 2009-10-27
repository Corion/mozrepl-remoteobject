#!perl -w
use strict;
use Test::More;

use MozRepl::RemoteObject;

diag "--- Loading object functionality into repl\n";

my $repl;
my $ok = eval {
    $repl = MozRepl::RemoteObject->install_bridge();
    1;
};
if (! $ok) {
    my $err = $@;
    plan skip_all => "Couldn't connect to MozRepl: $@";
} else {
    plan tests => 9;
};

# create a nested object
sub genObj {
    my ($repl,$val) = @_;
    my $rn = $repl->name;
    my $obj = $repl->expr(<<JS)
(function(repl, val) {
    return { bar: [ 'baz', { value: val } ] };
})($rn, "$val")
JS
}

my $foo = genObj($repl, 'deep');
isa_ok $foo, 'MozRepl::RemoteObject::Instance';

my $bar = $foo->{bar};
isa_ok $bar, 'MozRepl::RemoteObject::Instance';

my @elements = @{ $bar };
is 0+@elements, 2, 'We have two elements';

#diag $_ for @$bar;

my $baz = $bar->[0];
is $baz, 'baz', 'First array element retrieved';

my $baz2 = $bar->{0};
is $baz2, 'baz', 'First array element retrieved via hash key';

my $val = $bar->[1];
isa_ok $val, 'MozRepl::RemoteObject::Instance', 'Object retrieval from array';
is $val->{value}, 'deep', '... and the object contains our value';

push @{ $bar }, 'asdf';
is 0+@{ $bar }, 3, '... even pushing an element works';
is $bar->[-1], 'asdf', '... and the value is actually stored';