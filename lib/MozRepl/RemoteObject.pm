package MozRepl::RemoteObject;
use strict;

use vars qw[$repl $objBridge];      # this should become configurable, some day
use Scalar::Util qw(blessed refaddr); # this should become a soft dependency
use File::Basename;
use Encode qw(decode);
use JSON;
use Carp qw(croak cluck);
use MozRepl;

use overload '%{}' => '__as_hash',
             '@{}' => '__as_array',
             '=='  => '__object_identity',
             '""'  => sub { overload::StrVal $_[0] };

=head1 NAME

MozRepl::RemoteObject - treat Javascript objects as Perl objects

=head1 SYNOPSIS

    #!perl -w
    use strict;
    use MozRepl::RemoteObject;
    my $repl = MozRepl->new;
    $repl->setup({
        log => [qw/ error/],
        plugins => { plugins => [qw[ JSON2 ]] },
    });
    MozRepl::RemoteObject->install_bridge($repl);
      
    # get our root object:
    my $rn = $repl->repl;
    my $tab = MozRepl::RemoteObject->expr(<<JS);
        window.getBrowser().addTab()
    JS

    # Now use the object:
    my $body = $tab->{linkedBrowser}
                ->{contentWindow}
                ->{document}
                ->{body}
                ;
    $body->{innerHTML} = "<h1>Hello from MozRepl::RemoteObject</h1>";

    like $body->{innerHTML}, '/Hello from/', "We stored the HTML";

    $tab->{linkedBrowser}->loadURI('http://corion.net/');

=cut

use vars '$VERSION';
$VERSION = '0.01';

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

repl.callMethod = function(id,fn,args) { 
    var obj = repl.getLink(id);
    fn = obj[fn];
    return repl.wrapResults( fn.apply(obj, args));
};
})([% rn %]);
JS

# Take a JSON response and convert it to a Perl data structure
sub to_perl($) {
    local $_ = shift;
    s/^"//;
    s/"$//;
    my $res;
    # reraise JS errors from perspective of caller
    if (/^!!!\s+(.*)$/m) {
        croak "MozRepl::RemoteObject: $1";
    };
    $_ = decode('utf-8',$_); # hardcoded
    from_json($_);
};

# Unwrap the result, will in the future also be used
# to handle async events
sub unwrap_json_result {
    my ($self,$data) = @_;
    if ($data->{type}) {
        #warn $data->{type};
        return ($self->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
};

=head2 C<< MozRepl::RemoteObject->install_bridge [$repl] >>

Installs the Javascript C<< <-> >> Perl bridge. If you pass in
an existing L<MozRepl> instance, it must have L<MozRepl::Plugin::JSON2>
loaded.

By default, MozRepl::RemoteObject will set up its own MozRepl instance
and store it in $MozRepl::RemoteObject::repl .

=cut

sub install_bridge {
    my ($package, $_repl) = @_;
    return # already installed
        if (! $_repl and $repl);
    cluck "Overwriting existing object bridge"
        if ($repl and refaddr $repl != refaddr $_repl);
    $repl = $_repl;
    
    my $rn = $repl->repl;

    # Load the JS side of the JS <-> Perl bridge
    for my $c ($objBridge) {
        $c = "$c"; # make a copy
        $c =~ s/\[%\s+rn\s+%\]/$rn/g; # cheap templating
        next unless $c =~ /\S/;
        $repl->execute($c);
    };

    $repl
};

=head2 C<< MozRepl::RemoteObject->expr $js >>

Runs the Javascript passed in through C< $js > and links
the returned result to a Perl object or a plain
value, depending on the type of the Javascript result.

This is how you get at the initial Javascript object
in the object forest.

=cut

sub expr {
    my $package = shift;
    $package = ref $package || $package;
    my $js = shift;
    $js =~ s/\s/ /g;
    $js =~ s/(["'\\])/"\\$1"/ge;
    my $rn = $repl->repl;
    my $data = js_call_to_perl_struct(<<JS);
    (function(repl,code) {
        return repl.wrapResults(eval(code))
    })($rn,"$js")
JS
    return $package->unwrap_json_result($data);
}

sub activeObjects {
    my $rn = $repl->repl;
    my $data = to_perl($repl->execute(<<JS));
    // activeObjects
    $rn.linkedValues
JS
}

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

B<NOTE>: Assignment of references is not yet implemented.
So if you try to store a MozRepl::RemoteObject into
another MozRepl::RemoteObject, the Javascript side of things
will likely blow up.

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

Complex datastructures like (references to) arrays or hashes
are not yet supported.

=cut

sub AUTOLOAD {
    my $fn = $MozRepl::RemoteObject::AUTOLOAD;
    $fn =~ s/.*:://;
    my $self = shift;
    return $self->__invoke($fn,@_)
}

=head2 C<< $obj->__invoke(METHOD, ARGS)

The C<< ->__invoke() >> object method is an alternate way to
invoke Javascript methods. It is normally equivalent to 
C<< $obj->$method(@ARGS) >>. This function must be used if the
METHOD name contains characters not valid in a Perl variable name 
(like foreign language characters).
To invoke a Javascript objects native C<< __invoke >> method (if such a
thing exists), please use:

    $object->__invoke('__invoke', @args);

The same holds true for the other convenience methods implemented
by this package:

    __attr
    __setAttr
    __xpath
    __click
    expr
    ...

=cut

=head2 C<< $obj->transform_arguments(@args) >>

Transforms the passed in arguments to its string
representations.

Things that match C< /^[0-9]+$/ > get passed through.

MozRepl::RemoteObject instances
are transformed into strings that resolve to their
Javascript counterparts.

Everything else gets quoted and passed along as string.

There is no way to specify
Javascript global variables. Use the C<< ->expr >> method
to get an object representing these.

=cut

sub __transform_arguments {
    my $self = shift;
    map {
        if (/^[0-9]+$/) {
            $_
        } elsif (ref and blessed $_ and $_->isa(__PACKAGE__)) {
            sprintf "repl.getLink(%d)", $_->__id
        } elsif (ref) {
            croak "Got $_. Passing references around is not yet supported.";
        } else {
            sprintf '"%s"', quotemeta $_
        }
    } @_
};

sub __invoke {
    my ($self,$fn,@args) = @_;
    my $id = $self->__id;
    die unless $self->__id;
    $fn = quotemeta $fn;
    my $rn = $repl->repl;
    @args = $self->__transform_arguments(@args);
    local $" = ',';
    my $js = <<JS;
$rn.callMethod($id,"$fn",[@args])
JS
    my $data = js_call_to_perl_struct($js);
    return $self->unwrap_json_result($data);
}

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
    my $release_action;
    if ($release_action = $self->__release_action) {
        $release_action = <<JS;
    var self = repl.getLink(id);
        $release_action //
    ;self = null;
JS
    };
    $release_action ||= '';
    return unless $self->__id();
    my $rn = $repl->repl;
    my $data = MozRepl::RemoteObject::js_call_to_perl_struct(<<JS);
(function (repl,id) {$release_action
    repl.breakLink(id);
})($rn,$id)
JS
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
    my $rn = $repl->repl;
    $attr = quotemeta $attr;
    my $data = js_call_to_perl_struct(<<JS);
$rn.getAttr($id,"$attr")
JS
    return $self->unwrap_json_result($data);
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
    $attr = quotemeta $attr;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $repl->repl;
    my $data = MozRepl::RemoteObject::js_call_to_perl_struct(<<JS);
    // __setAttr
$rn.getLink($id)["$attr"]="$value"
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
    my $rn = $repl->repl;
    my $path = join ",", map { '"' . quotemeta($_) . '"'} @path;
    
    my $data = js_call_to_perl_struct(<<JS);
$rn.dive($id,[$path])
JS
    return $self->unwrap_json_result($data);
}

# Should this one be removed?
sub __inspect {
    my ($self,$attr) = @_;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $repl->repl;
    my $data = $repl->execute(<<JS);
    // __inspect
    (function(repl,id) {
        return repl.getLink(id)
    }($rn,$id))
JS
}

=head2 C<< $obj->keys() >>

Returns the names of all properties
of the javascript object as a list.

  $obj->__keys()

is identical to

  keys %$obj


=cut

sub __keys { # or rather, __properties
    my ($self,$attr) = @_;
    die unless $self;
    my $id = $self->__id;
    my $rn = $repl->repl;
    my $data = js_call_to_perl_struct(<<JS);
    (function(repl,id){
        var obj = repl.getLink(id);
        var res = [];
        for (var el in obj) {
            res.push(el);
        }
        return res
    }($rn,$id))
JS
    return @$data;
}

=head2 C<< $obj->values >>

Returns the values of all properties
as a list.

  $obj->values()
  
is identical to

  values %$obj

=cut

sub __values { # or rather, __properties
    my ($self,$attr) = @_;
    die unless $self;
    my $id = $self->__id;
    my $rn = $repl->repl;
    my $data = js_call_to_perl_struct(<<JS);
    (function(repl,id){
        var obj = repl.getLink(id);
        var res = [];
        for (var el in obj) {
            res.push(obj[el]);
        }
        return res
    }($rn,$id))
JS
    return @$data;
}

=head2 C<< $obj->__xpath QUERY [, REF] >>

Executes an XPath query and returns the node
snapshot result as a list.

This is a convenience method that should only be called
on HTMLdocument nodes.

=cut

sub __xpath {
    my ($self,$query,$ref) = @_; # $self is a HTMLdocument
    my $id = $self->__id;
    $ref ||= $self;
    $ref = $ref->__id;
    my $rn = $repl->repl;
    my $js = <<JS;
    (function(repl,id,q,ref) {
        var d = repl.getLink(id);
        var r = repl.getLink(ref);
        var xres = d.evaluate(q,r,null,XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null );
        var res = [];
        var c = 0;
        for ( var i=0 ; i < xres.snapshotLength; i++ )
        {
            // alert(i + ": " + xres.snapshotItem(i));
            res.push( repl.link( xres.snapshotItem(i)));
        };
        return res
    }($rn,$id,"$query",$ref))
JS
    my $elements = js_call_to_perl_struct($js);
    $self->link_ids(@$elements);
}

=head2 C<< $obj->__click >>

Sends a Javascript C<click> event to the object.

This is a convenience method that should only be called
on HTMLdocument nodes or their children.

=cut

sub __click {
    my ($self) = @_; # $self is a HTMLdocument or a descendant!
    my $id = $self->__id;
    my $rn = $repl->repl;
    my $js = <<JS;
    (function(repl,id) {
        var event = content.document.createEvent('MouseEvents');
        var target = repl.getLink(id);
        event.initMouseEvent('click', true, true, window,
                             0, 0, 0, 0, 0, false, false, false,
                             false, 0, null);
        target.dispatchEvent(event);
        }($rn,$id))
JS
    js_call_to_perl_struct($js);
}

=head2 C<< MozRepl::RemoteObject->new ID, onDestroy >>

This creates a new Perl object that's linked to the
Javascript object C<ID>. You usually do not call this
directly but use C<< MozRepl::RemoteObject->link_ids @IDs >>
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
    my ($package,$id,$release_action) = @_;
    my $self = {
        id => $id,
        release_action => $release_action,
    };
    bless $self, ref $package || $package;
};

sub link_ids {
    my $package = shift;
    map {
        $_ ? $package->new( $_ )
           : undef
    } @_
}


sub __object_identity {
    my ($self,$other) = @_;
    return if (! $other);
    die unless $self->__id;
    my $left = $self->__id;
    my $right = $other->__id;
    my $rn = $repl->repl;
    my $data = MozRepl::RemoteObject::js_call_to_perl_struct(<<JS);
    // __object_identity
$rn.getLink($left)===$rn.getLink($right)
JS
}

=head2 C<< js_call_to_perl_struct $js, $repl >>

Takes a scalar with JS code, executes it, and returns
the result as a Perl structure.

C<$repl> is optional and defaults to $MozRepl::RemoteObject::repl.

This will not (yet?) cope with objects on the remote side, so you
will need to make sure to call C<< $rn.link() >> on all objects
that are to persist across the bridge.

This is a very low level method. You are better advised to use
C<< MozRepl::RemoteObject->expr() >> as that will know
to properly wrap objects but leave other values alone.

=cut

sub js_call_to_perl_struct {
    my ($js,$_repl) = @_;
    $_repl ||= $repl;
    $js = "JSON.stringify( function(){ var res = $js; return { result: res }}())";
    my $d = to_perl($_repl->execute($js));
    $d->{result}
};


# tied interface reflection

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
    warn "FIRSTKEY: $tied";
    my $obj = $tied->{impl};
    $tied->{__keys} ||= [$tied->{impl}->__keys()];
    $tied->{__keyidx} = 0;
    $tied->{__keys}->[ $obj->{__keyidx}++ ];
};

sub NEXTKEY {
    my ($tied,$lastkey) = @_;
    warn "NEXTKEY: $tied";
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

=head1 TODO

=over 4

=item *

Implement proper automatic
quoting for things that look like a string instead of blindly
passing everything through.

=item *

Remove the reliance on the global C<$repl> and make
each object carry a reference to the C<$repl> that created
it. This will allow access to more than one C<$repl>.

=item *

Think about how to handle object identity.
Should C<Scalar::Util::refaddr> return true whenever
the Javascript C<===> operator returns true?

Also see L<http://perlmonks.org/?node_id=802912>

Currently not a pressing issue, hence postponed.

=item *

Consider whether MozRepl actually always delivers
UTF-8 as output, make charset configurable.

=item *

Create a lazy object release mechanism that adds object releases
to a queue and only sends them when either $repl goes out
of scope or another request (for a property etc.) is sent.

This is an optimization and hence gets postponed.

=item *

Add truely lazy objects that don't allocate their JS counterparts
until an C<< __attr() >> is requested or a method call is made.

This is an optimization and hence gets postponed.

=item *

Add proper stringification overloading.

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

Implement Perl-side event listeners as callbacks.

These would be executed by the receiving Perl side.

=item *

Document the ways how to call methods on the JS side when you have a
Perl method of the same name.

=item *

Implement fetching of more than one property at once through __attr()

=item *

Implement automatic reblessing of JS objects into Perl objects
based on a typemap.

=item *

On the Javascript side, there should be an event queue which
is returned (and purged) as out-of-band data with every response
to enable more polled events.

=item *

Find out how to make MozRepl actively send responses instead
of polling for changes.

=item *

Consider using/supporting L<AnyEvent> for better compatibility
with other mainloops.

=back

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