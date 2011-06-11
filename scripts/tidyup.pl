#!/usr/bin/env perl
use lib './inc/lib/perl5', './lib';
use strict;
use warnings;
use File::Util;
use File::Slurp;
use Perl::Tidy;
use Algorithm::Diff qw/diff/;
use YAML;
my ($f) = File::Util->new();
my @dirs_and_files = @ARGV;
if ( !@ARGV ) { @dirs_and_files = ( 'mud', $f->list_dir( './lib', '--recurse' ), $f->list_dir( './scripts', '--recurse' ) ); }
@ARGV = ();    # placate perltidy
my @perlfiles = grep { $_ eq 'mud' || /\.p[ml]$/i } @dirs_and_files;

print "Perl files:\n";
foreach my $file (@perlfiles) {
    my $contents = read_file($file);
    my $tidied   = '';
    perltidy( source => \$contents, destination => \$tidied );
    if ( $contents ne $tidied ) {
        printf "%-35s is NOT tidy => perltidy -b %s\n", $file, $file;
        system( 'perltidy', '-b', $file ) == 0
          or do { warn "Couldn't tidy $file: $?"; next };
        unlink "$file.bak" or die "Couldn't unlink .bak file: $!";
    }
    else {
        printf "%-35s is tidy\n", $file;
    }
}
print "Tidied\n";
