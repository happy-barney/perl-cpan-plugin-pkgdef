
use strict;
use warnings;

use Module::Build;

my $builder = Module::Build->new(
    module_name => 'CPAN::Plugin::PkgDef',
    license     => 'perl',
    dist_author => 'Branislav Zahradnik <barney@cpan.org>',
    dist_version_from => '1.0.0',
    requires => {
        'CPAN' => '2.06',
        'CPAN::Plugin' => 0,
        'CPAN::Shell' => 0,
        'File::Path' => 0,
        'File::Spec' => 0,
        'POSIX' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup => [ 'CPAN-Plugin-PkgDef-*' ],
    meta_merge => {
        resources => {
            repository => 'https://github.com/happy-barney/perl-cpan-plugin-pkgdef',
            bugtracker => 'https://github.com/happy-barney/perl-cpan-plugin-pkgdef/issues',
        },
    },
);
$builder->create_build_script();
