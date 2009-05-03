#!/usr/bin/perl -w
use strict;
use warnings;
use lib './lib';
use File::Slurp qw/slurp/;
use Av4::Telnet qw/%TELOPTS %TELOPTIONS/;

my $datafile = shift or die "Need datafile!\n";
die "Not a file: $datafile\n" if ( !-f $datafile );
my @data = slurp($datafile);

my $verbatim = shift;
$verbatim = 0 if (!defined $verbatim);

my $lineno = 0;
foreach my $dataline (@data) {
    $lineno++;
    my ( $direction, $handle, $arrdata ) =
      $dataline =~ /^(Sent|Received)\s.*\s(.*)\:\s*\[([\d\,]+)\]\s*$/;
    if ( !defined $direction || !defined $handle || !defined $arrdata ) {
        die "Line $lineno: regexp didn't catch!\n" if (!$verbatim);
        $arrdata = $dataline;
        $direction = 'Received';
    }
    my @arr;
    if ($verbatim) {
        @arr = map {ord $_} split('',$arrdata);
    } else {
        @arr = split( ',', $arrdata );
    }
    foreach (@arr) {
        printf(
            "%-10s %3d %-10s %-10s %s\n",
            $direction,
            $_,
            defined $TELOPTS{$_}    ? $TELOPTS{$_}    : '?',
            defined $TELOPTIONS{$_} ? $TELOPTIONS{$_} : '?',
            (
                  ( $_ == 10 || $_ == 13 )
                ? ( $_ == 10 ? 'x10' : 'x13' )
                : (
                    (
                        $_ == 27
                        ? 'ESC/OUTMARK (27)'
                        : (
                            (
                                     $_ >= 32
                                  && $_ < 126 ? ( sprintf "[%c] ", $_ ) : ( sprintf "?? ", $_ )
                            )
                        )
                    )
                )
            )
        );
    }
}
