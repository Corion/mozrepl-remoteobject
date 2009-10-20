use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'    => 'MozRepl::RemoteObject',
    'VERSION_FROM'  => 'lib/MozRepl/RemoteObject.pm', # finds $VERSION
    'PREREQ_PM'    => { 'MozRepl' => 0.06,
                        'Scalar::Util' => 0,
                        'JSON' => 2,
                      }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/MozRepl/RemoteObject.pm', # retrieve abstract from module
       AUTHOR     => 'Max Maischein <corion@cpan.org>') : ()),
);

1;
