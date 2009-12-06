#!perl -w
use strict;
use MozRepl::RemoteObject;
use Test::More;
use File::Spec;
use Cwd;
use File::Basename;

plan tests => 3;

my $bridge = MozRepl::RemoteObject->install_bridge();

my $openHUD = $bridge->declare(<<'JS');
function (url,name,params) {
    return window.open(url,name,params);
}
JS
isa_ok $openHUD, 'MozRepl::RemoteObject::Instance';

sub fileURL {
    my $fn = File::Spec->rel2abs(
                 File::Spec->catfile(dirname($0),$_[0]),
                 getcwd,
             );
    $fn =~ s!\\!/!g; # fakey "make file:// URL"
    "file://$fn"
}

my $hud = $openHUD->(fileURL("10-xul-hud.xul"),"hud","chrome");
isa_ok $hud, 'MozRepl::RemoteObject::Instance';
sleep 1;
$hud->close();
ok 1, "We closed the window properly";
