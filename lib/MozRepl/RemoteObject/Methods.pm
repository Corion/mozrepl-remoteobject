package MozRepl::RemoteObject::Methods;
use strict;
use Scalar::Util qw(blessed);

use vars qw[$VERSION];
$VERSION = '0.26';

=head1 NAME

MozRepl::RemoteObject::Methods - Perl methods for mozrepl objects

=head1 SYNOPSIS

  my @links = $obj->MozRepl::RemoteObject::Methods::xpath('//a');

This module holds the routines that previously lived
as injected object methods on I<all> Javascript objects.

=head1 METHODS

=head2 C<< $obj->MozRepl::RemoteObject::Methods::invoke(METHOD, ARGS) >>

The C<< invoke() >> object method is an alternate way to
invoke Javascript methods. It is normally equivalent to 
C<< $obj->$method(@ARGS) >>. This function must be used if the
METHOD name contains characters not valid in a Perl variable name 
(like foreign language characters).
To invoke a Javascript objects native C<< __invoke >> method (if such a
thing exists), please use:

    $object->MozRepl::RemoteObject::Methods::invoke('__invoke', @args);

This method can be used to call the Javascript functions with the
same name as other convenience methods implemented
in Perl:

    __attr
    __setAttr
    __xpath
    __click
    ...

=cut

sub invoke {
    my ($self,$fn,@args) = @_;
    my $id = $self->__id;
    die unless $self->__id;
    
    ($fn) = $self->MozRepl::RemoteObject::Methods::transform_arguments($fn);
    my $rn = bridge($self)->name;
    @args = $self->MozRepl::RemoteObject::Methods::transform_arguments(@args);
    local $" = ',';
    my $js = <<JS;
$rn.callMethod($id,$fn,[@args])
JS
    return bridge($self)->unjson($js);
}

=head2 C<< $obj->MozRepl::RemoteObject::Methods::transform_arguments(@args) >>

This method transforms the passed in arguments to their JSON string
representations.

Things that match C< /^(?:[1-9][0-9]*|0+)$/ > get passed through.
 
MozRepl::RemoteObject::Instance instances
are transformed into strings that resolve to their
Javascript global variables. Use the C<< ->expr >> method
to get an object representing these.
 
It's also impossible to pass a negative or fractional number
as a number through to Javascript, or to pass digits as a Javascript string.

=cut
 
sub transform_arguments {
    my $self = shift;
    my $json = bridge($self)->json;
    map {
        if (! defined) {
             'null'
        } elsif (/^(?:[1-9][0-9]*|0+)$/) {
            $_
        #} elsif (ref and blessed $_ and $_->isa(__PACKAGE__)) {
        } elsif (ref and blessed $_ and $_->isa('MozRepl::RemoteObject::Instance')) {
            sprintf "%s.getLink(%d)", bridge($_)->name, id($_)
        } elsif (ref and blessed $_ and $_->isa('MozRepl::RemoteObject')) {
            $_->name
        } elsif (ref and ref eq 'CODE') { # callback
            my $cb = $self->bridge->make_callback($_);
            sprintf "%s.getLink(%d)", bridge($self)->name,
                                      id($cb)
        } elsif (ref) {
            $json->encode($_);
        } else {
            $json->encode($_)
        }
    } @_
};

# Helper to centralize the reblessing
sub hash_get {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    my $res = $_[0]->{ $_[1] };
    bless $_[0], $class;
    $res
};

sub hash_get_set {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    my $k = $_[-1];
    my $res = $_[0]->{ $k };
    if (@_ == 3) {
        $_[0]->{$k} = $_[1];
    };
    bless $_[0], $class;
    $res
};

=head2 C<< $obj->MozRepl::RemoteObject::Methods::id >>

Readonly accessor for the internal object id
that connects the Javascript object to the
Perl object.

=cut

sub id { hash_get( $_[0], 'id' ) };

=head2 C<< $obj->MozRepl::RemoteObject::Methods::on_destroy >>

Accessor for the callback
that gets invoked from C<< DESTROY >>.

=cut

sub on_destroy { hash_get_set( @_, 'on_destroy' )};

=head2 C<< $obj->MozRepl::RemoteObject::Methods::bridge >>

Readonly accessor for the bridge
that connects the Javascript object to the
Perl object.

=cut

sub bridge { hash_get( $_[0], 'bridge' )};

=head2 C<< MozRepl::RemoteObject::Methods::as_hash($obj) >>

=head2 C<< MozRepl::RemoteObject::Methods::as_array($obj) >>

=head2 C<< MozRepl::RemoteObject::Methods::as_code($obj) >>

Returns a reference to a hash/array/coderef. This is used
by L<overload>. Don't use these directly.

=cut


sub as_hash {
    my $self = shift;
    tie my %h, 'MozRepl::RemoteObject::TiedHash', $self;
    \%h;
};

sub as_array {
    my $self = shift;
    tie my @a, 'MozRepl::RemoteObject::TiedArray', $self;
    \@a;
};

sub as_code {
    my $self = shift;
    my $class = ref $self;
    my $id = id($self);
    my $context = hash_get($self, 'return_context');
    $context = $context
               ? qq{,"$context"}
               : '';
    return sub {
        my (@args) = @_;
        my $bridge = bridge($self);
        
        my $rn = $bridge->name;
        @args = transform_arguments($self,@args);
        local $" = ',';
        my $js = <<JS;
    $rn.callThis($id,[@args]$context)
JS
        return $bridge->unjson($js);
    };
};

sub object_identity {
    my ($self,$other) = @_;
    return if (   ! $other 
               or ! ref $other
               or ! blessed $other
               or ! $other->isa('MozRepl::RemoteObject::Instance')
               or ! $self->isa('MozRepl::RemoteObject::Instance'));
    my $left = id($self)
        or die "Internal inconsistency - no id found for $self";
    my $right = id($other);
    my $bridge = bridge($self);
    my $rn = $bridge->name;
    my $data = $bridge->expr(<<JS);
$rn.getLink($left)===$rn.getLink($right)
JS
}

1;

__END__

=head1 SEE ALSO

L<MozRepl::RemoteObject> for the objects to use this with

=head1 REPOSITORY

The public repository of this module is 
L<http://github.com/Corion/mozrepl-remoteobject>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2011 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut