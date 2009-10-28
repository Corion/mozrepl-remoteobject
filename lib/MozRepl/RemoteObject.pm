package MozRepl::RemoteObject;
use strict;

use JSON;
use Carp qw(croak cluck);
use MozRepl;

=head1 NAME

MozRepl::RemoteObject - treat Javascript objects as Perl objects

=head1 SYNOPSIS

    #!perl -w
    use strict;
    use MozRepl::RemoteObject;
    
    # use $ENV{MOZREPL} or localhost:4242
    my $repl = MozRepl::RemoteObject->install_bridge();
    
    # get our root object:
    my $tab = $repl->expr(<<JS);
        window.getBrowser().addTab()
    JS

    # Now use the object:
    my $body = $tab->{linkedBrowser}
                ->{contentWindow}
                ->{document}
                ->{body}
                ;
    $body->{innerHTML} = "<h1>Hello from MozRepl::RemoteObject</h1>";

    $body->{innerHTML} =~ '/Hello from/'
        and print "We stored the HTML";

    $tab->{linkedBrowser}->loadURI('http://corion.net/');

=cut

use vars qw[$VERSION $objBridge];
$VERSION = '0.02';

# This should go into __setup__ and attach itself to $repl as .link()
$objBridge = <<JS;
(function(repl){
repl.link = function(obj) {
    // These values should go into a closure instead of attaching to the repl
    if (! repl.linkedVars) {
        repl.linkedVars = {};
        repl.linkedIdNext = 1;
    };
    
    if (obj) {
        repl.linkedVars[ repl.linkedIdNext ] = obj;
        return repl.linkedIdNext++;
    } else {
        return undefined
    }
}
repl.getLink = function(id) {
    return repl.linkedVars[ id ];
}

repl.breakLink = function(id) {
    delete repl.linkedVars[ id ];
}

repl.getAttr = function(id,attr) {
    var v = repl.getLink(id)[attr];
    return repl.wrapResults(v)
}

repl.wrapResults = function(v) {
    if (  v instanceof String
       || typeof(v) == "string"
       || v instanceof Number
       || typeof(v) == "number"
       || v instanceof Boolean
       || typeof(v) == "boolean"
       ) {
        return { result: v, type: null }
    } else {
        return { result: repl.link(v), type: typeof(v) }
    };
}

repl.dive = function(id,elts) {
    var obj = repl.getLink(id);
    var last = "<start object>";
    for (var idx=0;idx <elts.length; idx++) {
        var e = elts[idx];
        // because "in" doesn't seem to look at inherited properties??
        if (e in obj || obj[e]) {
            last = e;
            obj = obj[ e ];
        } else {
            throw "Cannot dive: " + last + "." + e + " is empty.";
        };
    };
    return repl.wrapResults(obj)
}

repl.callThis = function(id,args) {
    var obj = repl.getLink(id);
    return repl.wrapResults( obj.apply(obj, args));
}

repl.callMethod = function(id,fn,args) { 
    var obj = repl.getLink(id);
    var f = obj[fn];
    if (! f) {
        throw "Object has no function " + fn;
    }
    return repl.wrapResults( f.apply(obj, args));
};
})([% rn %]);
JS

# Take a JSON response and convert it to a Perl data structure
sub to_perl {
    my ($self,$js) = @_;
    local $_ = $js;
    s/^"//;
    s/"$//;
    # reraise JS errors from perspective of caller
    if (/^!!!\s+(.*)$/m) {
        croak "MozRepl::RemoteObject: $1";
    };
    $self->json->decode($_);
};

# Unwrap the result, will in the future also be used
# to handle async events
sub unwrap_json_result {
    my ($self,$data) = @_;
    if ($data->{type}) {
        return ($self->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
};

# Call JS and return the unwrapped result
sub unjson {
    my ($self,$js) = @_;
    my $data = $self->js_call_to_perl_struct($js);
    return $self->unwrap_json_result($data);    
};

=head1 BRIDGE SETUP

=head2 C<< MozRepl::RemoteObject->install_bridge %options >>

Installs the Javascript C<< <-> >> Perl bridge. If you pass in
an existing L<MozRepl> instance, it must have L<MozRepl::Plugin::JSON2>
loaded.

By default, MozRepl::RemoteObject will set up its own MozRepl instance
and store it in $MozRepl::RemoteObject::repl .

If C<repl> is not passed in, C<$ENV{MOZREPL}> will be used
to find the ip address and portnumber to connect to. If C<$ENV{MOZREPL}>
is not set, the default of C<localhost:4242> will be used.

If C<repl> is not a reference, it will be used instead of C<$ENV{MOZREPL}>.

To replace the default JSON parser, you can pass it in using the C<json>
option.

=head3 Connect to a different machine

If you want to connect to a Firefox instance on a different machine,
call C<< ->install_bridge >> as follows:

    MozRepl::RemoteObject->install_bridge("$remote_machine:4242");

=head3 Using an existing MozRepl

If you want to pass in a preconfigured L<MozRepl> object,
call C<< ->install_bridge >> as follows:

    my $repl = MozRepl->new;
    $repl->setup({
        log => [qw/ error info /],
        plugins => { plugins => [qw[ JSON2 ]] },
    });
    my $bridge = MozRepl::RemoteObject->install_bridge(repl => $repl);

=cut

sub install_bridge {
    my ($package, %options) = @_;
    $options{ repl } ||= $ENV{MOZREPL};
    $options{ log } ||= [qw/ error/];
    
    if (! ref $options{repl}) { # we have host:port
        my @host_port;
        if (defined $options{repl}) {
            $options{repl} =~ /^(.*):(\d+)$/
                or croak "Couldn't find host:port from [$options{repl}].";
            push @host_port, host => $1
                if defined $1;
            push @host_port, port => $2
                if defined $2;
        };
        $options{repl} = MozRepl->new();
        $options{repl}->setup({
            client => {
                @host_port,
                extra_client_args => {
                    binmode => 1,
                }
            },
            log => $options{ log },
            plugins => { plugins => [qw[ JSON2 ]] }, # I'm loading my own JSON serializer
        });
    };
    
    my $rn = $options{repl}->repl;
    $options{ json } ||= JSON->new->allow_nonref; # ->utf8;

    # Load the JS side of the JS <-> Perl bridge
    for my $c ($objBridge) {
        $c = "$c"; # make a copy
        $c =~ s/\[%\s+rn\s+%\]/$rn/g; # cheap templating
        next unless $c =~ /\S/;
        $options{repl}->execute($c);
    };
    
    $options{ functions } = {}; # cache

    bless \%options, $package
};

=head2 C<< $bridge->expr $js >>

Runs the Javascript passed in through C< $js > and links
the returned result to a Perl object or a plain
value, depending on the type of the Javascript result.

This is how you get at the initial Javascript object
in the object forest.

  my $window = $bridge->expr('window');
  print $window->{title};
  
You can also create Javascript functions and use them from Perl:

  my $add = $bridge->expr(<<JS);
      function (a,b) { return a+b }
  JS
  print $add->(2,3);

=cut

sub expr {
    my ($self,$js) = @_;
    $js = $self->json->encode($js);
    my $rn = $self->repl->repl;
    $js = <<JS;
    (function(repl,code) {
        return repl.wrapResults(eval(code))
    })($rn,$js)
JS
    return $self->unjson($js);
}

sub link_ids {
    my $self = shift;
    map {
        $_ ? MozRepl::RemoteObject::Instance->new( $self, $_ )
           : undef
    } @_
}

=head2 C<< $bridge->js_call_to_perl_struct $js >>

Takes a scalar with JS code, executes it, and returns
the result as a Perl structure.

This will not (yet?) cope with objects on the remote side, so you
will need to make sure to call C<< $rn.link() >> on all objects
that are to persist across the bridge.

This is a very low level method. You are better advised to use
C<< $bridge->expr() >> as that will know
to properly wrap objects but leave other values alone.

=cut

# This should go into its own package to clean up the namespace
sub js_call_to_perl_struct {
    my ($self,$js) = @_;
    my $repl = $self->repl;
    $js = "JSON.stringify( function(){ var res = $js; return { result: res }}())";
    my $d = $self->to_perl($repl->execute($js));
    $d->{result}
};

sub repl {$_[0]->{repl}};
sub json {$_[0]->{json}};
sub name {$_[0]->{repl}->repl};

=head2 C<< $bridge->declare($js) >>

Shortcut to declare anonymous JS functions
that will be cached in the bridge. This
allows you to use anonymous functions
in an efficient manner from your modules
while keeping the serialization features
of MozRepl::RemoteObject:

  my $js = <<'JS';
    function(a,b) {
        return a+b
    }
  JS
  my $fn = $self->bridge->declare($js);
  $fn->($a,$b);

The function C<$fn> will remain declared
on the Javascript side
until the bridge is torn down.

=cut

sub declare {
    my ($self,$js) = @_;
    $self->{functions}->{$js} ||= $self->expr($js);
};

package # hide from CPAN
    MozRepl::RemoteObject::Instance;
use strict;
use Carp qw(croak cluck);
use Scalar::Util qw(blessed refaddr);

use overload '%{}' => '__as_hash',
             '@{}' => '__as_array',
             '&{}' => '__as_code',
             '=='  => '__object_identity',
             '""'  => sub { overload::StrVal $_[0] };

=head1 HASH access

All MozRepl::RemoteObject objects implement
transparent hash access through overloading, which means
that accessing C<< $document->{body} >> will return
the wrapped C<< document.body >> object.

This is usually what you want when working with Javascript
objects from Perl.

Setting hash keys will try to set the respective property
in the Javascript object, but always as a string value,
numerical values are not supported.

=head1 ARRAY access

Accessing an object as an array will mainly work. For
determining the C<length>, it is assumed that the
object has a C<.length> method. If the method has
a different name, you will have to access the object
as a hash with the index as the key.

Note that C<push> expects the underlying object
to have a C<.push()> Javascript method, and C<pop>
gets mapped to the C<.pop()> Javascript method.

=cut

=head1 OBJECT IDENTITY

Object identity is currently implemented by
overloading the C<==> operator.
Two objects are considered identical
if the javascript C<===> operator
returns true.

  my $obj_a = MozRepl::RemoteObject->expr('window.document');
  print $obj_a->__id(),"\n"; # 42
  my $obj_b = MozRepl::RemoteObject->expr('window.document');
  print $obj_b->__id(), "\n"; #43
  print $obj_a == $obj_b; # true

=head1 CALLING METHODS

Calling methods on a Javascript object is supported.

All arguments will be autoquoted if they contain anything
other than ASCII digits (C<< [0-9] >>). There currently
is no way to specify that you want an all-digit parameter
to be put in between double quotes.

Passing MozRepl::RemoteObject objects as parameters in Perl
passes the proxied Javascript object as parameter to the Javascript method.

As in Javascript, functions are first class objects, the following
two methods of calling a function are equivalent:

  $window->loadURI('http://search.cpan.org/');
  
  $window->{loadURI}->('http://search.cpan.org/');

=cut

sub AUTOLOAD {
    my $fn = $MozRepl::RemoteObject::Instance::AUTOLOAD;
    $fn =~ s/.*:://;
    my $self = shift;
    return $self->__invoke($fn,@_)
}


=head1 OBJECT METHODS

=head2 C<< $obj->__invoke(METHOD, ARGS) >>

The C<< ->__invoke() >> object method is an alternate way to
invoke Javascript methods. It is normally equivalent to 
C<< $obj->$method(@ARGS) >>. This function must be used if the
METHOD name contains characters not valid in a Perl variable name 
(like foreign language characters).
To invoke a Javascript objects native C<< __invoke >> method (if such a
thing exists), please use:

    $object->__invoke('__invoke', @args);

The same method can be used to call the Javascript functions with the
same name as other convenience methods implemented
by this package:

    __attr
    __setAttr
    __xpath
    __click
    expr
    ...

=cut

sub __invoke {
    my ($self,$fn,@args) = @_;
    my $id = $self->__id;
    die unless $self->__id;
    
    ($fn) = $self->__transform_arguments($fn);
    my $rn = $self->bridge->name;
    @args = $self->__transform_arguments(@args);
    use Data::Dumper;
    local $" = ',';
    my $js = <<JS;
$rn.callMethod($id,$fn,[@args])
JS
    return $self->bridge->unjson($js);
}

=head2 C<< $obj->__transform_arguments(@args) >>

Transforms the passed in arguments to their string
representations.

Things that match C< /^[0-9]+$/ > get passed through.

MozRepl::RemoteObject::Instance instances
are transformed into strings that resolve to their
Javascript counterparts.

MozRepl::RemoteObject instances get transformed into their repl name.

Everything else gets quoted and passed along as string.

There is no way to specify
Javascript global variables. Use the C<< ->expr >> method
to get an object representing these.

=cut

sub __transform_arguments {
    my $self = shift;
    my $json = $self->bridge->json;
    map {
        if (! defined) {
            'null'
        } elsif (/^[0-9]+$/) {
            $_
        } elsif (ref and blessed $_ and $_->isa(__PACKAGE__)) {
            sprintf "%s.getLink(%d)", $self->bridge->name, $_->__id
        } elsif (ref and blessed $_ and $_->isa('MozRepl::RemoteObject')) {
            $_->name
        } elsif (ref) {
            $json->encode($_)
        } else {
            $json->encode($_)
        }
    } @_
};

=head2 C<< $obj->__id >>

Readonly accessor for the internal object id
that connects the Javascript object to the
Perl object.

=cut

sub __id {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    my $id = $_[0]->{id};
    bless $_[0], $class;
    $id
};

=head2 C<< $obj->bridge >>

Readonly accessor for the bridge
that connects the Javascript object to the
Perl object.

=cut

sub bridge {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    my $bridge = $_[0]->{bridge};
    bless $_[0], $class;
    $bridge
};

=head2 C<< $obj->__release_action >>

Accessor for Javascript code that gets executed
when the Perl object gets released.

=cut

sub __release_action {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    if (2 == @_) {
        $_[0]->{release_action} = $_[1];
    };
    my $release_action = $_[0]->{release_action};
    bless $_[0], $class;
    $release_action
};

sub DESTROY {
    my $self = shift;
    my $id = $self->__id();
    return unless $self->__id();
    my $release_action;
    if ($release_action = ($self->__release_action || '')) {
        $release_action = <<JS;
    var self = repl.getLink(id);
        $release_action //
    ;self = null;
JS
    };
    if ($self->bridge) { # not always there during global destruction
        my $rn = $self->bridge->name;
        my $data = $self->bridge->js_call_to_perl_struct(<<JS);
(function (repl,id) {$release_action
    repl.breakLink(id);
})($rn,$id)
JS
    };
}

=head2 C<< $obj->__attr ATTRIBUTE >>

Read-only accessor to read the property
of a Javascript object.

    $obj->__attr('foo')
    
is identical to

    $obj->{foo}

=cut

sub __attr {
    my ($self,$attr) = @_;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $self->bridge->repl->repl;
    $attr = $self->bridge->json->encode($attr);
    return $self->bridge->unjson(<<JS);
$rn.getAttr($id,$attr)
JS
}

=head2 C<< $obj->__setAttr ATTRIBUTE, VALUE >>

Write accessor to set a property of a Javascript
object.

    $obj->__setAttr('foo', 'bar')
    
is identical to

    $obj->{foo} = 'bar'

=cut

sub __setAttr {
    my ($self,$attr,$value) = @_;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $self->bridge->repl->repl;
    $attr = $self->bridge->json->encode($attr);
    ($value) = $self->__transform_arguments($value);
    my $data = $self->bridge->js_call_to_perl_struct(<<JS);
    // __setAttr
$rn.getLink($id)[$attr]=$value
JS
}

=head2 C<< $obj->__dive @PATH >>

Convenience method to quickly dive down a property chain.

If any element on the path is missing, the method dies
with the error message which element was not found.

This method is faster than descending through the object
forest with Perl, but otherwise identical.

  my $obj = $tab->{linkedBrowser}
                ->{contentWindow}
                ->{document}
                ->{body}

  my $obj = $tab->__dive(qw(linkedBrowser contentWindow document body));

=cut

sub __dive {
    my ($self,@path) = @_;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $self->bridge->repl->repl;
    (my $path) = $self->__transform_arguments(\@path);
    
    my $data = $self->bridge->unjson(<<JS);
$rn.dive($id,$path)
JS
}

=head2 C<< $obj->__keys() >>

Returns the names of all properties
of the javascript object as a list.

  $obj->__keys()

is identical to

  keys %$obj


=cut

sub __keys { # or rather, __properties
    my ($self,$attr) = @_;
    die unless $self;
    my $getKeys = $self->bridge->declare(<<'JS');
    function(obj){
        var res = [];
        for (var el in obj) {
            res.push(el);
        }
        return res
    }
JS
    return @{ $getKeys->($self) };
}

=head2 C<< $obj->__values >>

Returns the values of all properties
as a list.

  $obj->values()
  
is identical to

  values %$obj

=cut

sub __values { # or rather, __properties
    my ($self,$attr) = @_;
    die unless $self;
    my $getValues = $self->bridge->declare(<<'JS');
    function(obj){
        var res = [];
        for (var el in obj) {
            res.push(obj[el]);
        }
        return res
    }
JS
    return @{ $getValues->($self) };
}

=head2 C<< $obj->__xpath QUERY [, REF] >>

Executes an XPath query and returns the node
snapshot result as a list.

This is a convenience method that should only be called
on HTMLdocument nodes.

=cut

sub __xpath {
    my ($self,$query,$ref) = @_; # $self is a HTMLdocument
    $ref ||= $self;
    my $js = <<'JS';
    function(doc,q,ref) {
        var xres = doc.evaluate(q,ref,null,XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null );
        var res = [];
        var c = 0;
        for ( var i=0 ; i < xres.snapshotLength; i++ )
        {
            res.push( xres.snapshotItem(i));
        };
        return res
    }
JS
    my $snap = $self->bridge->declare($js);
    my $res = $snap->($self,$query,$ref);
    @{ $res }
}

=head2 C<< $obj->__click >>

Sends a Javascript C<click> event to the object.

This is a convenience method that should only be called
on HTMLdocument nodes or their children.

=cut

sub __click {
    my ($self) = @_; # $self is a HTMLdocument or a descendant!
    my $click = $self->bridge->declare(<<'JS');
    function(target) {
        var event = content.document.createEvent('MouseEvents');
        event.initMouseEvent('click', true, true, window,
                             0, 0, 0, 0, 0, false, false, false,
                             false, 0, null);
        target.dispatchEvent(event);
    }
JS
    $click->($self);
}

=head2 C<< MozRepl::RemoteObject->new bridge, ID, onDestroy >>

This creates a new Perl object that's linked to the
Javascript object C<ID>. You usually do not call this
directly but use C<< $bridge->link_ids @IDs >>
to wrap a list of Javascript ids with Perl objects.

The C<onDestroy> parameter should contain a Javascript
string that will be executed when the Perl object is
released.
The Javascript string is executed in its own scope
container with the following variables defined:

=over 4

=item *

C<self> - the linked object

=item *

C<id> - the numerical Javascript object id of this object

=item *

C<repl> - the L<MozRepl> Javascript C<repl> object

=back

This method is useful if you want to automatically
close tabs or release other resources
when your Perl program exits.

=cut

sub new {
    my ($package,$bridge, $id,$release_action) = @_;
    my $self = {
        id => $id,
        bridge => $bridge,
        release_action => $release_action,
    };
    bless $self, ref $package || $package;
};

sub __object_identity {
    my ($self,$other) = @_;
    return if (   ! $other 
               or ! ref $other
               or ! blessed $other
               or ! $other->isa(__PACKAGE__));
    die unless $self->__id;
    my $left = $self->__id;
    my $right = $other->__id;
    my $rn = $self->bridge->name;
    my $data = $self->bridge->js_call_to_perl_struct(<<JS);
    // __object_identity
$rn.getLink($left)===$rn.getLink($right)
JS
}

# tied interface reflection

=head2 C<< $obj->__as_hash >>

=head2 C<< $obj->__as_array >>

=head2 C<< $obj->__as_code >>

Returns a reference to a hash/array/coderef. This is used
by L<overload>. Don't use these directly.

=cut

sub __as_hash {
    my $self = shift;
    tie my %h, 'MozRepl::RemoteObject::TiedHash', $self;
    \%h;
};

sub __as_array {
    my $self = shift;
    tie my @a, 'MozRepl::RemoteObject::TiedArray', $self;
    \@a;
};

sub __as_code {
    my $self = shift;
    return sub {
        my (@args) = @_;
        my $id = $self->__id;
        die unless $self->__id;
        
        my $rn = $self->bridge->repl->repl;
        @args = $self->__transform_arguments(@args);
        local $" = ',';
        my $js = <<JS;
    $rn.callThis($id,[@args])
JS
        return $self->bridge->unjson($js);
    };
};

package # don't index this on CPAN
  MozRepl::RemoteObject::TiedHash;
use strict;

sub TIEHASH {
    my ($package,$impl) = @_;
    my $tied = { impl => $impl };
    bless $tied, $package;
};

sub FETCH {
    my ($tied,$k) = @_;
    my $obj = $tied->{impl};
    $obj->__attr($k)
};

sub STORE {
    my ($tied,$k,$val) = @_;
    my $obj = $tied->{impl};
    $obj->__setAttr($k,$val)
};

sub FIRSTKEY {
    my ($tied) = @_;
    my $obj = $tied->{impl};
    $tied->{__keys} ||= [$tied->{impl}->__keys()];
    $tied->{__keyidx} = 0;
    $tied->{__keys}->[ $tied->{__keyidx}++ ];
};

sub NEXTKEY {
    my ($tied,$lastkey) = @_;
    my $obj = $tied->{impl};
    $tied->{__keys}->[ $tied->{__keyidx}++ ];
};

1;

package # don't index this on CPAN
  MozRepl::RemoteObject::TiedArray;
use strict;

sub TIEARRAY {
    my ($package,$impl) = @_;
    my $tied = { impl => $impl };
    bless $tied, $package;
};

sub FETCHSIZE {
    my ($tied) = @_;
    my $obj = $tied->{impl};
    $obj->{length};
}

sub FETCH {
    my ($tied,$k) = @_;
    my $obj = $tied->{impl};
    $obj->__attr($k)
};

sub STORE {
    my ($tied,$k,$val) = @_;
    my $obj = $tied->{impl};
    $obj->__setAttr($k,$val)
};

sub PUSH {
    my $tied = shift;
    my $obj = $tied->{impl};
    for (@_) {
        $obj->push($_);
    };
};

sub POP {
    my $tied = shift;
    my $obj = $tied->{impl};
    for (@_) {
        $obj->pop($_);
    };
};

1;

__END__

=head1 ENCODING

The communication with the MozRepl plugin is done
through 7bit safe ASCII. The received bytes are supposed
to be UTF-8, but this seems not always to be the case.

Currently there is no way to specify a different encoding
on the fly. You have to replace or reconfigure
the JSON object in the constructor.

You can toggle the utf8'ness by calling

  $bridge->json->utf8;

=head1 TODO

=over 4

=item *

Implement C<EXISTS()> so we can use
C<< exists $foo->{onClick} >>.

=item *

For tests that connect to the outside world,
check/ask whether we're allowed to. If running
automated, skip.

=item *

Think more about how to handle object identity.
Should C<Scalar::Util::refaddr> return true whenever
the Javascript C<===> operator returns true?

Also see L<http://perlmonks.org/?node_id=802912>

=item *

Consider whether MozRepl actually always delivers
UTF-8 as output.

=item *

Properly encode all output that gets send towards
L<MozRepl> into the proper encoding.

=item *

Can we find a sensible implementation of string
overloading for JS objects? Should it be the
respective JS object type?

=item *

Create a lazy object release mechanism that adds object releases
to a queue and only sends them when either $repl goes out
of scope or another request (for a property etc.) is sent.

This would reduce the TCP latency when manually descending
through an object tree in a Perl-side loop.

This might introduce interesting problems when objects
get delayed until global destruction begins and the MozRepl
gets shut down before all object destructions could be sent.

This is an optimization and hence gets postponed.

=item *

Add truely lazy objects that don't allocate their JS counterparts
until an C<< __attr() >> is requested or a method call is made.

This is an optimization and hence gets postponed.

=item *

Potentially do away with attaching to the repl object and keep
all elements as anonymous functions referenced only by Perl variables.

This would have the advantage of centralizing the value wrapping/unwrapping
in one place, C<__invoke>, and possibly also in C<__as_code>. It would
also keep the precompiled JS around instead of recompiling it on
every access.

C<repl.wrapResults> would have to be handed around in an interesting
manner then though.

=item *

Add proper event wrappers and find a mechanism to send such events.

Having C<< __click() >> is less than desireable. Maybe blindly adding
the C<< click() >> method is preferrable.

=item *

Implement "notifications":

  gBrowser.addEventListener('load', function() { 
      repl.mechanize.update_content++
  });

The notifications would be sent as the events:
entry in any response from a queue, at least for the
synchronous MozRepl implementation.

=item *

Implement fetching of more than one property at once through __attr()

=item *

Implement automatic reblessing of JS objects into Perl objects
based on a typemap instead of blessing everything into
MozRepl::RemoteObject.

=item *

On the Javascript side, there should be an event queue which
is returned (and purged) as out-of-band data with every response
to enable more polled events.

This would lead to implementing a full two-way message bus.

=item *

Create a convenience wrapper to define anonymous Perl subroutines
and stuff them into Javascript as anonymous Javascript functions.

These would be executed by the receiving Perl side when it
reads the requests from the event queue.

=item *

Find out how to make MozRepl actively send responses instead
of polling for changes.

This would lead to implementing a full two-way message bus.

=item *

Consider using/supporting L<AnyEvent> for better compatibility
with other mainloops.

This would lead to implementing a full two-way message bus.

=back

=head1 SEE ALSO

L<Win32::OLE> for another implementation of proxy objects

L<http://wiki.github.com/bard/mozrepl> - the MozRepl 
FireFox plugin homepage

=head1 REPOSITORY

The public repository of this module is 
L<http://github.com/Corion/mozrepl-remoteobject>.

=head1 AUTHOR

Max Maischein C<corion@cpan.org>

=head1 COPYRIGHT (c)

Copyright 2009 by Max Maischein C<corion@cpan.org>.

=head1 LICENSE

This module is released under the same terms as Perl itself.

=cut