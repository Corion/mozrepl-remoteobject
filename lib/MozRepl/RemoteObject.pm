package MozRepl::RemoteObject;
use strict;

use vars qw[$repl $objBridge];      # this should become configurable, some day
use Scalar::Util qw(weaken); # this should become a soft dependency
use File::Basename;
use Encode qw(decode);
use JSON;
use Carp qw(croak);
use MozRepl;

use overload '%{}' => '__as_hash',
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

    $tab->{linkedBrowser}->loadURI('"http://corion.net/"');

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
        repl.linkedVars[ [% rn %].linkedIdNext ] = obj;
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

})([% rn %]);
JS

# Take a JSON response and convert it to a Perl data structure
sub to_perl($) {
    local $_ = shift;
    s/^"//;
    s/"$//;
    my $res;
    # reraise JS errors
    if (/^!!!\s+(.*)$/m) {
        croak "MozRepl::RemoteObject: $1";
    };
    #$_ = decode('ISO-8859-1',$_); # hardcoded
    $_ = decode('utf-8',$_); # hardcoded
    #(my $dump = $_) =~ s/([\x00-\x1F])/sprintf '%02x', ord($1)/ge;;
    #warn "[[$dump]]";
    if (! eval {
        $res = from_json($_);
        1
    }) {
        my $err = $@;
        #warn $err;
        #warn substr $_, 400, 100;
        #while (/(.{32})\t\t\r?\n\r?\n/gms) {
        #    warn pos;
        #    warn "[$1]";
        #};
        die $err;
    };
    $res
};

=head2 C<< js_call_to_perl_struct $js >>

Takes a scalar with JS code, executes it, and returns
the result as a Perl structure.

This will not (yet?) cope with objects on the remote side, so you
will need to make sure to call C<< $rn.link() >> on all objects
that are to persist across the bridge.

This is a very low level method. You are better advised to use
C<< MozRepl::RemoteObject->expr() >> as that will know
to properly wrap objects but leave other values alone.

=cut

sub js_call_to_perl_struct {
    my $js = shift;
    $js = "JSON.stringify( function(){ var res = $js; return { result: res }}())";
    my $d = to_perl($repl->execute($js));
    $d->{result}
};

sub install_bridge {
    my ($package, $_repl) = @_;
    $repl = $_repl;
    
    # Load our JSON2 support into FF
    #my $json2 = File::Spec->catfile( File::Spec->rel2abs( dirname $0 ), 'js', 'json2.js' );
    #$json2 =~ tr[\\][/];
    #$repl->repl_load({ uri => "file://$json2" });

    my $rn = $repl->repl;

    # Load the JS side of the JS <-> Perl bridge
    for my $c ($objBridge) { #split m!^//.*$!m, $objBridge) {
        $c = "$c";
        $c =~ s/\[%\s+rn\s+%\]/$rn/g;
        next unless $c =~ /\S/;
        #warn "Loading [[$_]]";
        $repl->execute($c);
    };

};

sub __id {
    my $class = ref $_[0];
    bless $_[0], "$class\::HashAccess";
    my $id = $_[0]->{id};
    bless $_[0], $class;
    $id
};

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

sub AUTOLOAD {
    my $self = shift;
    my $id = $self->__id;
    die unless $self->__id;
    my $fn = $MozRepl::RemoteObject::AUTOLOAD;
    $fn =~ s/.*:://;
    $fn = quotemeta $fn;
    my $rn = $repl->repl;
    local $" = ',';
    # XXX Should go into object bridge
    my $js = <<JS;
    (function(repl,id,fn,args) { 
        var obj = repl.getLink(id);
        fn = obj[fn];
        return repl.wrapResults( fn.apply(obj, args));
    })($rn,$id,"$fn",[@_])
JS
    my $data = js_call_to_perl_struct($js);
    if ($data->{type}) {
        #warn $data->{type};
        return ($self->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
}

sub __attr {
    my ($self,$attr) = @_;
    die unless $self->__id;
    my $id = $self->__id;
    my $rn = $repl->repl;
    $attr = quotemeta $attr;
    my $data = js_call_to_perl_struct(<<JS);
$rn.getAttr($id,"$attr")
JS
    if ($data->{type}) {
        #warn $data->{type};
        return ($self->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
}

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
    if ($data->{type}) {
        return ($self->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
}

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
    # XXX should this become a static method as well?
    my $data = js_call_to_perl_struct(<<JS);
    (function(repl,code) {
        return repl.wrapResults(eval(code))
    })($rn,"$js")
JS
    if ($data->{type}) {
        #warn $data->{type};
        return ($package->link_ids( $data->{result} ))[0]
    } else {
        return $data->{result}
    };
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

=cut

# tied interface reflection

sub __as_hash {
    my $self = shift;
    tie my %h, 'MozRepl::RemoteObject::Tied', $self;
    \%h;
};

package
  MozRepl::RemoteObject::Tied;
use strict;
use Data::Dumper;
use Scalar::Util qw(refaddr);

use vars qw(%tied);

sub TIEHASH {
    my ($package,$impl) = @_;
    my $tied = { impl => $impl };
    bless $tied, $package;
};

sub FETCH {
    my ($tied,$k) = @_;
    #warn "FETCH $tied / $k";
    #warn Dumper $tied;
    my $obj = $tied->{impl};
    $obj->__attr($k)
};

sub STORE {
    my ($tied,$k,$val) = @_;
    #die "STORE not implemented";
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

=head1 TODO

=over 4

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

Add stringification overloading.

=item *

Add proper event wrappers and find a mechanism to send such events.

Having C<< __click() >> is less than desireable. Maybe blindly adding
the C<< click() >> method is preferrable.

=item *

Document the ways how to call methods on the JS side when you have a
Perl method of the same name.

=item *

Implement fetching of more than one property at once through __attr()

=item *

Implement automatic reblessing of JS objects into Perl objects
based on a typemap.

=item *

Spin off HTML::Display::MozRepl as soon as I find out how I can
load an arbitrary document via MozRepl into a C<document>.

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

=cut

1;