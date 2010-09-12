#!/usr/bin/env perl
use strict;
use warnings;
use Benchmark qw/:all/;

use Inline C  => <<'END_INLINE_C';
    unsigned char __colors[8] = "xrgybpcw";
    // Canonical, used in the mud
    unsigned char getcolor(unsigned char clrchar) {
        char i = 0;
        for ( i = 0; i < 8; i++ ) {
            if (   clrchar     == __colors[i] ) { return i; }
            if ( ( clrchar+32) == __colors[i] ) { return i; }
        }
        return (unsigned char) -1;
    }
    // Optimized Inline::C version
    unsigned char opt_getcolor(unsigned char clrchar) {
        switch (clrchar) {
            case 120: case 88: return 0;
            case 114: case 82: return 1;
            case 103: case 71: return 2;
            case 121: case 89: return 3;
            case 98:  case 66: return 4;
            case 112: case 80: return 5;
            case 99:  case 67: return 6;
            case 119: case 87: return 7;
            default: return (unsigned char) -1;
        }
    }
END_INLINE_C

### old perl-only version
{
    my @colors = map { ord } qw/x r g y b p c w/;
    sub perl_getcolor {
        my $clrchar = shift;
        for ( 0 .. $#colors ) {
            return $_ if ( $clrchar == $colors[$_] );
            return $_ if ( ( $clrchar + 32 ) == $colors[$_] );
        }
        return 255;
    }
}

### Optimized Perl version
{
    #my @colors = map { ord } qw/x r g y b p c w/;
    # 120 114 103 121 98 112 99 119
    sub opt_perl_getcolor {
        #$_[0]+32 == 120 && return 0; # 120 - 32 : 88; etc
        $_[0] == 120 && return 0;
        $_[0] == 88  && return 0; # $_[0]+32 == 120
        $_[0] == 114 && return 1;
        $_[0] == 82  && return 1;
        $_[0] == 103 && return 2;
        $_[0] == 71  && return 2;
        $_[0] == 121 && return 3;
        $_[0] == 89  && return 3;
        $_[0] == 98  && return 4;
        $_[0] == 66  && return 4;
        $_[0] == 112 && return 5;
        $_[0] == 80  && return 5;
        $_[0] == 99  && return 6;
        $_[0] == 67  && return 6;
        $_[0] == 119 && return 7;
        $_[0] == 87  && return 7;
        return 255;
    }
}

### Give each possibility to cache stuff
for (qw/x r g y b p c w ~/) {
    getcolor(ord $_);
    getcolor(ord uc $_);
    opt_getcolor(ord $_);
    opt_getcolor(ord uc $_);
    perl_getcolor(ord $_);
    perl_getcolor(ord uc $_);
    opt_perl_getcolor(ord $_);
    opt_perl_getcolor(ord uc $_);
}


my $result = timethese(
    1_500_000,
    {
        'Opt Inline::C version' => sub {
            for (qw/x r g y b p c w ~/) {
                opt_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                opt_getcolor(ord $_)
            }
        },
        'Inline::C version' => sub {
            for (qw/x r g y b p c w ~/) {
                getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                getcolor(ord $_)
            }
        },
        'Pure Perl version' => sub {
            for (qw/x r g y b p c w ~/) {
                perl_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                perl_getcolor(ord $_)
            }
        },
        'Opt Perl version' => sub {
            for (qw/x r g y b p c w ~/) {
                opt_perl_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                opt_perl_getcolor(ord $_)
            }
        },
    }
);
cmpthese($result);

__END__
Benchmark: timing 1500000 iterations of Inline::C version, Opt Inline::C version, Opt Perl version, Pure Perl version...
Inline::C version:  5 wallclock secs ( 4.45 usr +  0.00 sys =  4.45 CPU) @ 337078.65/s (n=1500000)
Opt Inline::C version:  4 wallclock secs ( 3.83 usr +  0.00 sys =  3.83 CPU) @ 391644.91/s (n=1500000)
Opt Perl version: 16 wallclock secs (15.18 usr +  0.00 sys = 15.18 CPU) @ 98814.23/s (n=1500000)
Pure Perl version: 45 wallclock secs (43.77 usr +  0.01 sys = 43.78 CPU) @ 34262.22/s (n=1500000)
                          Rate Pure Perl version Opt Perl version Inline::C version Opt Inline::C version
Pure Perl version      34262/s                --             -65%              -90%                  -91%
Opt Perl version       98814/s              188%               --              -71%                  -75%
Inline::C version     337079/s              884%             241%                --                  -14%
Opt Inline::C version 391645/s             1043%             296%               16%                    --
