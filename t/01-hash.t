#!perl -w
use strict;
use Data::Dumper;
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
    plan tests => 10;
};

# create a nested object
sub genObj {
    my ($repl,$val) = @_;
    my $rn = $repl->name;
    my $obj = $repl->expr(<<JS)
(function(repl, val) {
    return { bar: { baz: { value: val } }, foo: 1 };
})($rn, "$val")
JS
}

my $foo = genObj($repl, 'deep');
isa_ok $foo, 'MozRepl::RemoteObject::Instance';

my $bar = $foo->{bar};
isa_ok $bar, 'MozRepl::RemoteObject::Instance';

my $baz = $bar->{baz};
isa_ok $baz, 'MozRepl::RemoteObject::Instance';

my $val = $baz->{value};
is $val, 'deep';

$val = $baz->{nonexisting};
is $val, undef, 'Nonexisting properties return undef';

$baz->{ 'test' } = 'foo';
is $baz->{ test }, 'foo', 'Setting a value works';

my @keys = sort $foo->__keys;
is_deeply \@keys, ['bar','foo'], 'We can get at the keys';

@keys = sort keys %$foo;
is_deeply \@keys, ['bar','foo'], 'We can get at the keys'
    or diag Dumper \@keys;

my @values = $foo->__values;
is scalar @values, 2, 'We have two values';

@values = values %$foo;
is scalar @values, 2, 'We have two values';