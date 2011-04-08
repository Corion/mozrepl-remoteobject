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
        prompt => qr/^(?:\.\.\.\.>\s)*(repl\d*)>\s+/m,
        execute_stack => [],
        %args
    } => $class;    
};

sub log {
    my ($self,$level,@info) = @_;
    if ($self->{log}->{$level}) {
        warn "[$level] $_\n" for @info;
    };
};

sub setup_async {
    my $cb = pop;
    my ($self,%options) = @_;
    my $client = delete $options{ client } || {};
    $client->{port} ||= 4242;
    $client->{host} ||= 'localhost';
    
    my $json = MozRepl::Plugin::JSON2->new();
    $cb ||= AnyEvent->condvar;
    
    $self->{log} = +{ map { $_ => 1 } @{$options{ log }} };
    
    my $hdl = AnyEvent::Handle->new(
        connect => [ $client->{host}, $client->{port} ],
        #on_connect => sub { $connected->send },
    );

   
    # Read the welcome banner
    $hdl->push_read( regex => $self->{prompt}, sub {
        my ($handle, $data) = @_;
        $data =~ /$self->{prompt}/m
            or croak "Couldn't find REPL name in '$data'";
        $self->{name} = $1;
        $self->log('debug', "Repl name is '$1'");
        
        # Load our JSON handler into Firefox
        # Fake this so we can keep the same API
        push @{ $self->{execute_stack}}, sub {
            # Tell anybody interested that we're connected now
            $self->log('debug', "Connected now");
            $cb->($self)
        };
        
        # This calls $self->execute, which pops the callback from 
        # the stack and runs it
        $json->setup( $self );
    });
    $self->{hdl} = $hdl;
    
    $cb
};

sub setup {
    my ($self,%options) = @_;
    my $done = AnyEvent->condvar;
    $self->setup_async(%options, sub { $done->send });
    $done->recv;
};

sub repl { $_[0]->{name} };
sub hdl  { $_[0]->{hdl} };

sub execute_async {
    my ($self, $command, $cb) = @_;
    $self->log( debug => "Sending [$command]");
    # XXX Log command going out
    $cb ||= AnyEvent->condvar;
    $self->hdl->push_write( $command );
    $self->log(debug => "Waiting for " . $self->{prompt});

    # Push a log-peek
    #$self->hdl->push_read(sub {
    #    # XXX Log data coming in
    #    warn "Received data <$_[0]->{rbuf}>";
    #    0 # continue dumping
    #});
    
    $self->hdl->push_read( regex => $self->{prompt}, 
        timeout => 10,
        sub {
        $_[1] =~ s/$self->{prompt}$//;
        # XXX Log data coming in
        $self->log(debug => "Received data", $_[1]);
        $cb->($_[1]);
    });
    $cb
};

sub execute {
    my $self = shift;
    my $cv = $self->execute_async( @_ );
    if (my $cb = pop @{ $self->{execute_stack} }) {
        # pop a callback if we have an internal callback to make
        $cv->cb( $cb );
    } else {
        $cv->recv
    };
};

1;