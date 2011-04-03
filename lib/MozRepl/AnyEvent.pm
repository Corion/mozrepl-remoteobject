package MozRepl::AnyEvent;
use strict;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Strict;
use Carp qw(croak);
use MozRepl::Plugin::JSON2;

=head1 NAME

AnyEvent-enabled MozRepl client

=cut

sub new {
    # ...
    my ($class, %args) = @_;
    bless {
        hdl => undef,
        prompt => qr/^(repl\d*)>/m,
        %args
    } => $class;    
};

sub setup_async {
    my ($self,%options) = @_;
    my $client = delete $options{ client } || {};
    $client->{port} ||= 4242;
    $client->{host} ||= 'localhost';
    
    my $json = MozRepl::Plugin::JSON2->new();
    
    # XXX Handle logging
    # log => $options{ log },
    my $complete = AnyEvent->condvar;
    
    my $hdl = AnyEvent::Handle->new(
        connect => [ $client->{host}, $client->{port} ],
        #on_connect => sub { $connected->send },
    );
    
    # Read the welcome banner
    $hdl->push_read( regex => $self->{prompt}, sub {
        my ($handle, $data) = @_;
        $data =~ /$self->{prompt}/m
            or croak "Couldn't find REPL name in '$data'";
        # XXX Log repl name
        $self->{name} = $1;
        warn "Repl name is '$1'";
        
        # Load our JSON handler into Firefox
        $json->setup( $self );
        # Here we could also load the other plugins
        
        # Tell anybody interested that we're connected now
        $complete->send($self);
    });
    $self->{hdl} = $hdl;
    
    $complete
};

sub setup {
    my ($self,%options) = @_;
    $self->setup_async(%options)->recv;
};

sub repl { $_[0]->{name} };
sub hdl  { $_[0]->{hdl} };

sub execute_async {
    my ($self, $command, $cont) = @_;
    warn "Sending command";
    # XXX Log command going out
    my $cont ||= AnyEvent->condvar;
    $self->hdl->push_write( $command );
    warn "Waiting for " . $self->{prompt};
    $self->hdl->push_read( regex => $self->{prompt}, sub {
        $_[1] =~ s/$self->{prompt}$//;
        # XXX Log data coming in
        warn "Received data $_[1]";
        $cont->($_[1]);
    });
    $cont
};

sub execute {
    my $self = shift;
    $self->execute_async( @_ )->recv
};

1;