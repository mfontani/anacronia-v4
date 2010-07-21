package Mud::Help;
use Moose;
has 'level'    => ( is => 'rw', isa => 'Num', required => 1, );
has 'keywords' => ( is => 'rw', isa => 'Str', required => 1, );
has 'data'     => ( is => 'rw', isa => 'Str', required => 1, );
__PACKAGE__->meta->make_immutable();
no Moose;

package main;
use strict;
use warnings;
use Fatal qw/open close/;
use lib './lib';
use Av4::Ansi;

sub areaparse {
    my $fn = shift;
    open my $F, '<', $fn;
    my @area;
    my $section      = 0;
    my $subsection   = 0;
    my $sectionlevel = 0;
    my $data         = '';
    my $lineno       = 0;
    while (<$F>) {
        my $line = $_;
        $lineno++;
        next if ( $line =~ /^\s*$/ );
        if ( !$section ) {    # looking for #SECTIONNAME
            die "Line $lineno: havent found any section name!\n"
              if ( $line !~ /^\#\w+\s*$/ );
            $section = $line;
            $section =~ s/^\#//g;
            $section =~ s/\s*$//g;
            print "Line $lineno: section $section\n";
            next;
        }
        if ( !$subsection ) {    # on help file, level + keywords
            die "Line $lineno: doesnt match number + letters + ~\n"
              unless ( my ( $level, $keywords ) = $line =~ /^\s*\-?(\d*)\s*(.*)\~\s*$/ );
            print "Line $lineno: Level $level keywords $keywords\n";
            $subsection   = $keywords;
            $sectionlevel = $level;
            next;
        }

        # for help, until line containing ~
        if ( $line =~ /^\s*\~\s*$/ ) {
            push(
                @area,
                Mud::Help->new(
                    level    => $sectionlevel,
                    keywords => $subsection,
                    data     => $data
                )
            );
            $subsection = 0;
            $data       = '';
            print "Line $lineno: Got help page for $subsection\n";
            next;
        }
        $data .= $line;
    }
    close $F;
    return \@area;
}

sub areahelp {
    my ( $helps, $which ) = @_;
    foreach (@$helps) {
        return $_ if ( $_->keywords =~ /\b$which/i );
    }
    return undef;
}

my $fn = shift or die "Need filename\n";
my $helps = areaparse($fn);

my %stats;
foreach (@$helps) {

    # counts & and ^ per ->data
    my $data = $_->data;
    $data =~ s/(\&\&|\^\^)/\~/g;    # away
    $data =~ s/[^\&\^]//g;
    print $_->keywords, ' => ', length $data, "\n";
    $stats{ $_->keywords } = length $data;    # count of & and ^
}

print "Most coloured:\n";
my @sorted = sort { $stats{$b} <=> $stats{$a} } keys %stats;
for ( 1 .. 3 ) {
    last if ( !defined $sorted[$_] );
    print $sorted[$_], ' - ', $stats{ $sorted[$_] }, "\n";
}

print "Parsed. Enter help name\n";
my $which = <>;
chomp($which);
my $found = areahelp( $helps, $which );
print Av4::Ansi::ansify( $found->data ) if defined $found;
