use strict;

warn "Starting the build for Av4..\n";

my $PWD = `pwd`;
chomp $PWD;

my @cpanmoptions = ( '-n', );
push @cpanmoptions, '--mirror', '/opt/minicpan',          '--mirror-only' if ( -d '/opt/minicpan' );
push @cpanmoptions, '--mirror', '/STUFF/minicpan',        '--mirror-only' if ( -d '/STUFF/minicpan' );
push @cpanmoptions, '--mirror', '/linuxbackups/minicpan', '--mirror-only' if ( -d '/linuxbackups/minicpan' );

my $PERL = $PWD . '/perl5/perlbrew/perls/perl-5.14.2/bin/perl';

if ( ! -f $PERL ) {
  warn "\n\nYou do not yet have Perl 5.14.2 under $PERL, I will now build it.\n\n";
  my @build_perlbrew = (
    qw<PERLBREW_ROOT=$(pwd)/perl5/perlbrew PERLBREW_HOME=$(pwd)/perl5/perlbrew $(pwd)/perl5/perlbrew/bin/perlbrew install>,
    qw< --notest perl-5.14.2 -D uselargefiles>,
    qw<-D cccflags=-fpic -D optimize=-O2 -D usehrplib>,
    #qw<-D usethreads>, # no need for threads for Av4
    qw<-D use64bitall>
  );
  open my $brewit, '>', 'brewit.sh' or die "Could not create brewit.sh: $!";
  print $brewit join(' ', @build_perlbrew);
  close $brewit;
  system(qw</bin/bash ./brewit.sh>) == 0 or die "Could not build perl-5.14.2 :(";
  unlink 'brewit.sh';
  warn "\n\nBuild done. Now launching Build.PL with the newly created perl\n\n";
  exec($PERL,$0);
}

# Ensure we're running under 5.14.2
use Config;
if ( $Config{version} ne '5.14.2' ) {
  warn "You are using Perl $Config{version}; relaunching with $PERL...";
  exec($PERL,$0);
} else {
  warn "You are using Perl 5.14.2.. Good!\n";
}

our @required_modules = (

    # Installer
    'Module::Build',
    'File::Spec',

    # MUD
    'XSLoader',
    'YAML',
    'Time::HiRes',
    'AnyEvent',
    'AnyEvent::Gearman::Client',
    'Class::XSAccessor',
    'Compress::Raw::Zlib',
    'Digest::MD5',
    'Cache::Memcached::Fast',
    'Log::Log4perl',
    'Devel::Size',
    'utf8::all',

    # Tests
    'Test::Differences',

    # Profiling
    'Devel::NYTProf',

    # Charting
    'Chart::Clicker',
    'Text::CSV_XS',

);

our %platform_specific_modules;

if ( $^O eq 'darwin' ) {
  $platform_specific_modules{'Event'}     = 0;
  $platform_specific_modules{'IO::Async'} = 0;
} else {
  $platform_specific_modules{'EV'}        = 0;
}

###### Install / ensure all prereqs are installed.
###### Required ones in the order they are given, platform-specific after those.
print "Installing/ensuring all prerequisites are present...\n";
for my $module ( @required_modules, keys %platform_specific_modules ) {
  system($PERL,$PWD . '/cpanm', @cpanmoptions, $module) == 0 or die "Could not install $module.. BUG!\n";
}
print "Prerequisites OK\n";

use File::Spec;
use lib File::Spec->catdir('lib');    # use our self to install

# We use Module::Build to test & install itself.
use Module::Build;

my $build = Module::Build->new(
    module_name   => 'Av4',
    dist_version  => '0.01',
    dist_abstract => 'A Multi User Dungeon',
    license       => 'gpl',
    requires      => {
        ( map { $_ => 0 } @required_modules ),
        %platform_specific_modules,
    },
    recursive_test_files => 1,
    sign                 => 0,
    create_readme        => 1,
    create_license       => 1,
);

$build->create_build_script;

print "\n\n";
print "Launching ./Build...\n";
print qx{$PERL ./Build};

print "\n\n";
print "Done; you should be able to launch ./mud and all from ./scripts/\n\n";
print "You should use $PERL to launch all the executables.\n\n";

# vim:ts=2:sw=2:et:sta
