package MozRepl::RemoteObject::Methods;
use strict;
use Scalar::Util qw(blessed);

use vars qw[$VERSION];
$VERSION = '0.24';

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
    my $rn = $self->bridge->name;
    @args = $self->MozRepl::RemoteObject::Methods::transform_arguments(@args);
    local $" = ',';
    my $js = <<JS;
$rn.callMethod($id,$fn,[@args])
JS
    return $self->bridge->unjson($js);
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
    my $json = $self->bridge->json;
    map {
        if (! defined) {
             'null'
        } elsif (/^(?:[1-9][0-9]*|0+)$/) {
            $_
        #} elsif (ref and blessed $_ and $_->isa(__PACKAGE__)) {
        } elsif (ref and blessed $_ and $_->isa('MozRepl::RemoteObject::Instance')) {
            sprintf "%s.getLink(%d)", $_->bridge->name, $_->__id
        } elsif (ref and blessed $_ and $_->isa('MozRepl::RemoteObject')) {
            $_->name
        } elsif (ref and ref eq 'CODE') { # callback
            my $cb = $self->bridge->make_callback($_);
            sprintf "%s.getLink(%d)", $self->bridge->name,
                                      $cb->__id
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