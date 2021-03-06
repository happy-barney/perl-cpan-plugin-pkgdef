package CPAN::Plugin::RPMSpec;
use base 'CPAN::Plugin::Pkgdef';

use strict;
use warnings;

use File::Path;
use File::Spec;
require POSIX;

sub __accessor {
    my ($class, $key) = @_;
    no strict 'refs';
    *{$class . '::' . $key} = sub {
        my $self = shift;
        if (@_) {
            $self->{$key} = shift;
        }
        return $self->{$key};
    };
}
BEGIN { __PACKAGE__->__accessor($_) for qw(dir dir_default) }

our $VERSION = '1.0.0';

our %Config;
our %Default = (
    group        => 'Development/Libraries',
    buildroot    => "%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)",
    installdirs  => "vendor",
    install_root => '/usr',
    file_owner   => 'root',
    perl         => 'perl',
    who_am_i     => '',
    release      => "1%{?dist}",
);

sub new {                                # ;
    my ($self, %params) = @_;

    $self->SUPER::new (%Default, %params)
}

######################################################################
sub plugin_requires {                    # ; modules used by this module
    +(
        'File::Basename',
        'CPAN::DistnameInfo',
    );
}

######################################################################
sub format_min_version {                 # ;
    my ($self, $v) = @_;
    $v = 0 unless defined $v;

    defined $v && length $v && $v > 0 ? " >= $v" : "";
}

######################################################################
sub format_is_version {                  # ;
    my ($self, $v) = @_;
    $v = 0 unless defined $v;

    defined $v && length $v && $v > 0 ? " = $v" : "";
}

######################################################################
sub format_capability {                  # ;
    my ($self, $module, $version) = @_;

    "$self->{perl}($module)" . $version;
}

######################################################################
sub post_test {
    my ($self, $do) = @_;
    $self = $self->new (distribution_object => $do);

    $self->{installlib} = $self->{installdirs} . ($self->is_xs ? "arch" : "lib");
    $self->{date}     = POSIX::strftime("%a %b %d %Y", gmtime);

    $self->make_specfile;
}

######################################################################
sub get_pkg_name {                       # ;
    my ($self) = @_;

    join '-', $self->{perl}, $self->SUPER::get_pkg_name;
}

######################################################################
sub gen_rpm_description {                # ;
    <<EOF;

%description
%{summary}

EOF
}

######################################################################
sub get_rpm_provides {                   # ;
    my ($self) = @_;

    local $_;
    map +(
        [ Provides => $self->format_capability (
            $_->[0],
            $self->format_is_version ($_->[1]),
        )]
    ), $self->get_pkg_provides;
}

######################################################################
sub get_rpm_build_requires {             # ;
    my ($self) = @_;

    local $_;
    +(
        [ BuildRequires => "$self->{perl}(:MODULE_COMPAT_%(eval \"`%{__perl} -V:version`\"; echo \$version))" ],
        map +(
            [ BuildRequires => $self->format_capability (
                $_->[0],
                $self->format_min_version ($_->[1]),
            ) ]
        ), $self->get_pkg_build_requires,
    );
}

######################################################################
sub get_rpm_requires {                   # ;
    my ($self) = @_;

    local $_;
    +(
        [ Requires => "$self->{perl}(:MODULE_COMPAT_%(eval \"`%{__perl} -V:version`\"; echo \$version))" ],
        map +(
            [ Requires => $self->format_capability (
                $_->[0],
                $self->format_min_version ($_->[1]),
            )]
        ), $self->get_pkg_requires,
    );
}

######################################################################
sub gen_rpm_header {                     # ;
    my ($self) = @_;

    local $_;
    my @header = (
        [ Name      => $self->get_pkg_name ],
        [ Version   => $self->get_pkg_version ],
        [ Summary   => $self->get_pkg_summary ],
        [ License   => $self->get_pkg_license ],
        [ URL       => $self->get_pkg_url ],
        [ Source0   => $self->get_pkg_source_url ],
        [ BuildRoot => $self->{buildroot} ],
        [ Release   => $self->{release} ],
        (grep $self->is_xs, [ BuildArch => 'noarch' ]),

        $self->get_rpm_provides,
        $self->get_rpm_requires,
        $self->get_rpm_build_requires,
    );

    join "\n", map sprintf ('%-*s %s', 16, $_->[0] . ':', $_->[1]), @header;
}

######################################################################
sub gen_rpm_meta {                       # ;
    my ($self) = @_;

    +(
        $self->gen_rpm_header,
        $self->gen_rpm_description,
    );
}

######################################################################
sub gen_rpm_prep {                       # ;
    my ($self) = @_;

    my $name    = $self->SUPER::get_pkg_name;
    my $version = $self->get_pkg_version;

    <<EOF;
%prep
%setup -q -n ${name}-${version}

EOF
}

######################################################################
sub gen_rpm_defines {                    # ;
    <<EOF;
%define _use_internal_dependency_generator     0
    my $self = shift;
    my $distribution_object = shift;
    my $distribution = $distribution_object->pretty_id;
    unless ($CPAN::META->has_inst("CPAN::DistnameInfo")){
        $CPAN::Frontend->mydie("CPAN::DistnameInfo not installed; cannot continue");
    }
    my $d = CPAN::Shell->expand("Distribution",$distribution)
        or $CPAN::Frontend->mydie("Unknowns distribution '$distribution'\n");
    my $build_dir = $d->{build_dir} or $CPAN::Frontend->mydie("Distribution has not been built yet, cannot proceed");
    my %contains = map {($_ => undef)} $d->containsmods;
    my @m;
    my $width = 16;
    my $header = sub {
        my($header,$value) = @_;
        push @m, sprintf("%-s:%*s%s\n", $header, $width-length($header), "", $value);
    };
    my $dni = CPAN::DistnameInfo->new($distribution);
    my $dist = $dni->dist;
    my $summary = CPAN::Shell->_guess_manpage($d,\%contains,$dist);
    $header->("Name", "perl-$dist");
    my $version = $dni->version;
    $header->("Version", $version);
    $header->("Release", "1%{?dist}");
#Summary:        Template processing system
#Group:          Development/Libraries
#License:        GPL+ or Artistic
#URL:            http://www.template-toolkit.org/
#Source0:        http://search.cpan.org/CPAN/authors/id/A/AB/ABW/Template-Toolkit-%{version}.tar.gz
#Patch0:         Template-2.22-SREZIC-01.patch
#BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
    for my $h_tuple
        ([Summary    => $summary],
         [Group      => "Development/Libraries"],
         [License    =>],
         [URL        =>],
         [BuildRoot  => "%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)"],
         [Requires   => "perl(:MODULE_COMPAT_%(eval \"`%{__perl} -V:version`\"; echo \$version))"],
        ) {
        my($h,$v) = @$h_tuple;
        $v = "unknown" unless defined $v;
        $header->($h, $v);
    }
    $header->("Source0", sprintf(
                                 "http://search.cpan.org/CPAN/authors/id/%s/%s/%s",
                                 substr($distribution,0,1),
                                 substr($distribution,0,2),
                                 $distribution
                                ));
    require POSIX;
    my @xs = glob "$build_dir/*.xs"; # quick try
    unless (@xs) {
        require ExtUtils::Manifest;
        my $manifest_file = "$build_dir/MANIFEST";
        my $manifest = ExtUtils::Manifest::maniread($manifest_file);
        @xs = grep /\.xs$/, keys %$manifest;
    }
    if (! @xs) {
        $header->('BuildArch', 'noarch');
    }
    for my $k (sort keys %contains) {
        my $m = CPAN::Shell->expand("Module",$k);
        my $v = $contains{$k} = $m->cpan_version;
        my $vspec = $v eq "undef" ? "" : " = $v";
        $header->("Provides", "perl($k)$vspec");
    }
    if (my $prereq_pm = $d->{prereq_pm}) {
        my %req;
        for my $reqkey (keys %$prereq_pm) {
            while (my($k,$v) = each %{$prereq_pm->{$reqkey}}) {
                $req{$k} = $v;
            }
        }
        if (-e "$build_dir/Build.PL" && ! exists $req{"Module::Build"}) {
            $req{"Module::Build"} = 0;
        }
        for my $k (sort keys %req) {
            next if $k eq "perl";
            my $v = $req{$k};
            my $vspec = defined $v && length $v && $v > 0 ? " >= $v" : "";
            $header->(BuildRequires => "perl($k)$vspec");
            next if $k =~ /^(Module::Build)$/; # MB is always only a
                                               # BuildRequires; if we
                                               # turn it into a
                                               # Requires, then we
                                               # would have to make it
                                               # a BuildRequires
                                               # everywhere we depend
                                               # on *one* MB built
                                               # module.
            $header->(Requires => "perl($k)$vspec");
        }
    }
    push @m, "\n%define _use_internal_dependency_generator     0
%define __find_requires %{nil}
%define __find_provides %{nil}

EOF
}

######################################################################
sub gen_rpm_build_with_makefile {        # ;
    my ($self) = @_;

        <<EOF
%build
%{__perl} Makefile.PL INSTALLDIRS=$self->{installdirs}%{?optimize: OPTIMIZE="%{optimize}"} < /dev/null
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
make pure_install DESTDIR=%{buildroot}
find %{buildroot} -type f -name .packlist -exec rm -f {} ';'
find %{buildroot} -type f -name '*.bs' -size 0 -exec rm -f {} ';'
find %{buildroot} -depth -type d -exec rmdir {} 2>/dev/null ';'
%{_fixperms} %{buildroot}/*

%check
make test

EOF
}

######################################################################
sub gen_rpm_build_with_build {           # ;
    my ($self) = @_;

    # see http://www.redhat.com/archives/rpm-list/2002-July/msg00110.html about RPM_BUILD_ROOT vs %{buildroot}
    # FIXME: at least vendor
    <<EOF;
%build
%{__perl} Build.PL --installdirs=vendor --libdoc installvendorman3dir
./Build

%install
rm -rf \$RPM_BUILD_ROOT
./Build install destdir=\$RPM_BUILD_ROOT create_packlist=0
find \$RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null \;
%{_fixperms} \$RPM_BUILD_ROOT/*

%check
./Build test

EOF
}

######################################################################
sub gen_rpm_build {                      # ;
    my ($self) = @_;

    return $self->gen_rpm_build_with_makefile
      if -e File::Spec->catfile ($self->build_dir, "Build.PL");

    return $self->gen_rpm_build_with_makefile
      if -e File::Spec->catfile ($self->build_dir, "Makefile.PL");

    my $distribution = $self->distribution;
    $self->frontend->mydie ("'$distribution' has neither a Build.PL nor a Makefile.PL\n");
}

######################################################################
sub gen_rpm_clean {                      # ;
    <<EOF
%clean
rm -rf %{buildroot}
EOF
}

######################################################################
sub gen_rpm_files {                      # ;
    my ($self) = @_;

    my @doc = grep { -e File::Spec->catfile ($self->build_dir, $_) } qw(README Changes);
    my @exe = map {
        File::Spec->catfile ($self->{install_root}, 'bin', File::Basename::basename ($_))
    } @{ $self->distribution->_exe_files };
    unshift @exe, "%{_mandir}/man1/*.1*" if @exe;

    my $exe_stanza = join "\n", @exe;

    <<EOF;
%files
%defattr(-,$self->{file_owner},$self->{file_owner},-)
%doc @doc
%{perl_$self->{installlib}/*
%{_mandir}/man3/*.3*
$exe_stanza

EOF
}

######################################################################
sub gen_rpm_changelog {                  # ;
    my ($self) = @_;
    my $version = $self->get_pkg_version;

    <<EOF;
%changelog
* $self->{date} $self->{who_am_i} - ${version}-1
- autogenerated by _specfile() in CPAN.pm

EOF
}

######################################################################
sub make_specfile {                      # ;
    my ($self, $data) = @_;

    $self->output (
        $self->gen_rpm_defines,
        $self->gen_rpm_meta,
        $self->gen_rpm_prep,
        $self->gen_rpm_build,
        $self->gen_rpm_clean,
        $self->gen_rpm_files,
        $self->gen_rpm_changelog
    );
}

######################################################################
sub output {
    my ($self, @m) = @_;
    my $name = $self->get_pkg_name;

    my $file = File::Spec->catfile ($self->{dir}, "$name.spec");

    my $ret = join "", @m;
    File::Path::mkpath($self->{dir});
    open my $specout, ">", $file
      or $CPAN::Frontend->mydie ("Unable open file: $file: $!");
    $CPAN::Frontend->myprint ($ret) if $self->{stdout};
    print $specout $ret;
    $CPAN::Frontend->myprint("Wrote $file");
    1;
}

######################################################################

package CPAN::Plugin::Pkgdef;

1;

__END__

=pod

=head1 NAME

CPAN::Plugin::Pkgdef - generate RPM spec file for distribution

=head1 CONFIGURATION

=head2 dir

where to store spec files.
todo: default

=head2 stdout

if set to true value, generated spec file will be displayed on stdout

=cut


