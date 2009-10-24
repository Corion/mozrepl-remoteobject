#!perl -w
use strict;
use Test::More tests => 2;

use MozRepl::RemoteObject;

# use $ENV{MOZREPL} or localhost:4242
my $repl = MozRepl::RemoteObject->install_bridge();

# get our root object:
my $rn = $repl->repl;
my $tab = MozRepl::RemoteObject->expr(<<JS);
    window.getBrowser().addTab()
JS

isa_ok $tab, 'MozRepl::RemoteObject', 'Our tab';

# Now use the object:
my $body = $tab->{linkedBrowser}
            ->{contentWindow}
            ->{document}
            ->{body}
            ;
$body->{innerHTML} = "<h1>Hello from MozRepl::RemoteObject</h1>";

like $body->{innerHTML}, '/Hello from/', "We stored the HTML";

# Don't connect to the outside:
#$tab->{linkedBrowser}->loadURI('http://corion.net/');

# close our tab again:
$tab->__release_action('window.getBrowser().removeTab(self)');
undef $tab;