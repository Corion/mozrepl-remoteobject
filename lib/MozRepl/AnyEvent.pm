package MozRepl::AnyEvent;
use strict;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Strict;
use Carp qw(croak);
use MozRepl::Plugin::JSON2;

use vars qw[$VERSION];
$VERSION = '0.23';

=head1 NAME

AnyEvent-enabled MozRepl client

=head1 SYNOPSIS

  use MozRepl::RemoteObject;
  $ENV{ MOZREPL_CLASS } = 'MozRepl::AnyEvent';
  my $bridge = MozRepl::RemoteObject->install_bridge();

This module provides a compatible API to L<MozRepl> solely
for what L<MozRepl::RemoteObject> uses. It does not
provide plugin support. If you want a fully compatible
AnyEvent-enabled L<MozRepl>, please consider porting L<Net::Telnet>
to L<AnyEvent::Handle>.

=head1 METHODS

=head2 C<< MozRepl::AnyEvent->new( %options ) >>

Creates a new instance.

Options

=over 4

=item *

C<log> - arrayref of log levels to enable

Currently only C<debug> is implemented, which will dump some information.

  log => [qw[debug],

=item *

C<hdl> - a premade L<AnyEvent::Handle> to talk to Firefox (optional)

=item *

C<prompt> - the regex that defines the repl prompt to look for.

Default is 

  prompt => qr/^(?:\.+>\s)*(repl\d*)>\s+/m

=back

=cut

sub new {
    my ($class, %args) = @_;
    bless {
        hdl => undef,
        prompt => qr/^(?:\.+>\s)*(repl\d*)>\s+/m,
        # The execute stack is an ugly hack to enable synchronous
        # execution within MozRepl::AnyEvent while still having
        # at most one ->recv call outstanding.
        # Ideally, this facility would go into AnyEvent itself.
        execute_stack => [],
        %args
    } => $class;    
};

=head2 C<< $repl->log( $level, @info ) >>

Prints the information to STDERR if logging is enabled
for the level.

=cut

sub log {
    my ($self,$level,@info) = @_;
    if ($self->{log}->{$level}) {
        warn "[$level] $_\n" for @info;
    };
};

=head2 C<< $repl->setup_async( $options ) >>

  my $repl = MozRepl::AnyEvent->setup({
      client => { host => 'localhost',
                  port => 4242,
                },
       log   => ['debug'],
       cv    => $cv,
  });

Sets up the repl connection. See L<MozRepl>::setup for detailed documentation.

The optional CV will get the repl through C<< ->send() >>.

Returns the CV to wait on that signals when setup is done.

=cut

sub setup_async {
    my ($self,$options) = @_;
    my $client = delete $options->{ client } || {};
    $client->{port} ||= 4242;
    $client->{host} ||= 'localhost';
    $options->{log} ||= [];
    my $cb = delete $options->{cv} || AnyEvent->condvar;
    
    my $json = MozRepl::Plugin::JSON2->new();
    
    $self->{log} = +{ map { $_ => 1 } @{$options->{ log }} };
    
    my $hdl = $self->{hdl} || AnyEvent::Handle->new(
        connect => [ $client->{host}, $client->{port} ],
        on_error => sub {
            $self->log('error',$_[2]);
            $self->{error} = $_[2];
            $cb->send();
            undef $cb;
            undef $self;
        },
        
        on_connect => sub {
            my ($hdl,$host,$port) = @_;
            $self->log('debug', "Connected to $host:$port");
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
                    $cb->send($self)
                };
                
                # This calls $self->execute, which pops the callback from 
                # the stack and runs it
                $json->setup( $self );
            });
        },
    );
   
    # Read the welcome banner
    $self->{hdl} = $hdl;
    
    $cb
};

=head2 C<< $repl->setup(...) >>

Synchronous version of C<< ->setup_async >>, provided
for API compatibility. This one will do a C<< ->recv >> call
inside.

=cut

sub setup {
    my ($self,$options) = @_;
    my $done = $self->setup_async($options);
    my @res = $done->recv;
    if (not @res=$done->recv) {
        # reraise error
        die $self->{error}
    };
};

=head2 C<< $repl->repl >>

Returns the name of the repl in Firefox.

=cut

sub repl { $_[0]->{name} };


=head2 C<< $repl->hdl >>

Returns the socket handle of the repl.

=cut

sub hdl  { $_[0]->{hdl} };

=head2 C<< $repl->execute_async( $command, $cb ) >>

    my $cv = $repl->execute_async( '1+1' );
    # do stuff
    my $two = $cv->recv;
    print "1+1 is $two\n";

Sends a command to Firefox for execution. Returns
the condvar to wait for the response.

=cut

sub execute_async {
    my ($self, $command, $cb) = @_;
    $self->log( info => "Sending command", $command);
    $cb ||= AnyEvent->condvar;
    $self->hdl->push_write( $command );
    $self->log(debug => "Waiting for prompt", $self->{prompt});

    # Push a log-peek
    #$self->hdl->push_read(sub {
    #    $self->log(debug => "Received data", $_[0]->{rbuf});
    #    return $_[0]->{rbuf} =~ /repl\d*> /;
    #});
    
    $self->hdl->push_read( regex => $self->{prompt}, 
        timeout => 10,
        sub {
        $_[1] =~ s/$self->{prompt}$//;
        $self->log(info => "Received data", $_[1]);
        $cb->($_[1]);
    });
    $cb
};

=head2 C<< $repl->execute( ... ) >>

Synchronous version of C<< ->execute_async >>. Internally
calls C<< ->recv >>. Provided for API compatibility.

=cut

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

=head1 SEE ALSO

L<MozRepl> for the module defining the API

L<AnyEvent> for AnyEvent

=head1 REPOSITORY

The public repository of this module is 
L<http://github.com/Corion/mozrepl-remoteobject>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2009-2011 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut