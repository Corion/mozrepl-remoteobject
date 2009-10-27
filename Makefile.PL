use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'MozRepl::RemoteObject',
    'LICENSE'      => 'perl',
    'VERSION_FROM' => 'lib/MozRepl/RemoteObject.pm', # finds $VERSION
    'PREREQ_PM'    => { 'MozRepl' => 0.06,
                        'Scalar::Util' => 0,
                        'JSON' => 2,
                        'Encode' => 0,
                        'JSON' => 2,
                        'File::Basename' => 0,
                        'parent' => 0,
                        'WWW::Mechanize' => 0, # for WWW::Mechanize::Link
                      }, # e.g., Module::Name => 1.1
    'ABSTRACT_FROM' => 'lib/MozRepl/RemoteObject.pm', # retrieve abstract from module
    'AUTHOR'        => 'Max Maischein <corion@cpan.org>'),
);

1;
