#!/usr/bin/perl
use strict;
use warnings;
use File::Util;
use File::Slurp;
use Perl::Tidy;
use Algorithm::Diff qw/diff/;
use YAML;
my ($f) = File::Util->new();
my (@dirs_and_files) = $f->list_dir( '.', '--recurse' );
my @perlfiles = grep { /\.p[ml]$/i } @dirs_and_files;

print "Perl files:\n";
foreach my $file (@perlfiles) {
    my $contents = read_file($file);
    my $tidied   = '';
    perltidy( source => \$contents, destination => \$tidied );
    if ( $contents ne $tidied ) {
        printf "%-30s is NOT tidy => perltidy -b %s\n", $file, $file;
        system( 'perltidy', '-b', $file ) == 0
          or warn "Couldn't tidy $file: $?";
    } else {
        printf "%-30s is tidy\n", $file;
    }
}
print "Tidied\n";
