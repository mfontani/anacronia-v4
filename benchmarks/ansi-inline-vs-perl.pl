#!/usr/bin/env perl
use strict;
use warnings;
use Av4::Ansi;
use Benchmark qw/:all/;

### old perl-only version
{
    my $colors = 'xrgybpcw';    #'xrgObpcwzRGYBPCW';
    my @colors = map { ord } qw/x r g y b p c w/;
    my ( $amp, $car, $bang ) = (ord('&'), ord('^'),ord('!'));
    sub perl_getcolor {
        my $clrchar = shift;
        for ( 0 .. $#colors ) {
            return $_ if ( $clrchar == $colors[$_] );
            return $_ if ( ( $clrchar + 32 ) == $colors[$_] );
        }
        return 255;
    }
}

my $result = timethese(
    1_500_000,
    {
        'Inline::C version' => sub {
            for (qw/x r g y b p c w/) {
                Av4::Ansi::getcolor(ord $_)
            }
        },
        'Pure Perl version' => sub {
            for (qw/x r g y b p c w/) {
                perl_getcolor(ord $_)
            }
        },
    }
);
cmpthese($result);

