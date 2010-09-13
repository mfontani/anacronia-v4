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

### Lookup hash Perl version -- thanks illusori
{
    my @colors = qw/x r g y b p c w/;
    my %colors = map { ord $colors[$_] => $_, ord uc $colors[$_] => $_ } 0..$#colors;
    sub hash_perl_getcolor {
        return exists $colors{$_[0]} ? $colors{$_[0]} : 255;
    }
}

### Array Lookup Perl version -- thanks illusori
{
    my @colors = qw/x r g y b p c w/;
    my @lookup;
    for (0..$#colors) {
        $lookup[ ord    $colors[$_] ] = $_;
        $lookup[ ord uc $colors[$_] ] = $_;
    }
    use YAML;
    sub lookup_perl_getcolor {
        return defined $lookup[ $_[0] ] ? $lookup[ $_[0] ] : 255;
    }
}

### Give each possibility to cache stuff
for (qw/x r g y b p c w ~/) {
    my $lc = getcolor(ord $_);
    my $uc = getcolor(ord uc $_);
    opt_getcolor(ord $_) == $lc
        or die "opt_getcolor( ord $_ ) returns wrong value";
    opt_getcolor(ord uc $_) == $uc
        or die "opt_getcolor( uc ord $_ ) returns wrong value";
    perl_getcolor(ord $_) == $lc
        or die "opt_getcolor( ord $_ ) returns wrong value";
    perl_getcolor(ord uc $_) == $uc
        or die "opt_getcolor( uc ord $_ ) returns wrong value";
    opt_perl_getcolor(ord $_) == $lc
        or die "opt_getcolor( ord $_ ) returns wrong value";
    opt_perl_getcolor(ord uc $_) == $uc
        or die "opt_getcolor( uc ord $_ ) returns wrong value";
    hash_perl_getcolor(ord $_) == $lc
        or die "opt_getcolor( ord $_ ) returns wrong value";
    hash_perl_getcolor(ord uc $_) == $uc
        or die "opt_getcolor( uc ord $_ ) returns wrong value";
    lookup_perl_getcolor(ord $_) == $lc
        or die "opt_getcolor( ord $_ ) returns wrong value";
    lookup_perl_getcolor(ord uc $_) == $uc
        or die "opt_getcolor( uc ord $_ ) returns wrong value";
}


my $result = timethese(
    1_500_000,
    {
        'Opt Inline::C' => sub {
            for (qw/x r g y b p c w ~/) {
                opt_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                opt_getcolor(ord $_)
            }
        },
        'Inline::C' => sub {
            for (qw/x r g y b p c w ~/) {
                getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                getcolor(ord $_)
            }
        },
        'Pure Perl' => sub {
            for (qw/x r g y b p c w ~/) {
                perl_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                perl_getcolor(ord $_)
            }
        },
        'Opt Perl' => sub {
            for (qw/x r g y b p c w ~/) {
                opt_perl_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                opt_perl_getcolor(ord $_)
            }
        },
        'Hash Perl' => sub {
            for (qw/x r g y b p c w ~/) {
                hash_perl_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                hash_perl_getcolor(ord $_)
            }
        },
        'Lookup Perl' => sub {
            for (qw/x r g y b p c w ~/) {
                lookup_perl_getcolor(ord $_)
            }
            for (qw/X R G Y B P C W ~/) {
                lookup_perl_getcolor(ord $_)
            }
        },
    }
);
cmpthese($result);

__END__
Benchmark: timing 1500000 iterations of Hash Perl, Inline::C, Lookup Perl, Opt Inline::C, Opt Perl, Pure Perl...
 Hash Perl: 11 wallclock secs (10.27 usr +  0.00 sys = 10.27 CPU) @ 146056.48/s (n=1500000)
 Inline::C:  4 wallclock secs ( 4.13 usr +  0.00 sys =  4.13 CPU) @ 363196.13/s (n=1500000)
Lookup Perl:  9 wallclock secs ( 8.61 usr +  0.00 sys =  8.61 CPU) @ 174216.03/s (n=1500000)
Opt Inline::C:  3 wallclock secs ( 3.64 usr +  0.00 sys =  3.64 CPU) @ 412087.91/s (n=1500000)
  Opt Perl: 14 wallclock secs (14.13 usr +  0.00 sys = 14.13 CPU) @ 106157.11/s (n=1500000)
 Pure Perl: 43 wallclock secs (42.49 usr +  0.01 sys = 42.50 CPU) @ 35294.12/s (n=1500000)
                  Rate Pure Perl Opt Perl Hash Perl Lookup Perl Inline::C Opt Inline::C
Pure Perl      35294/s        --     -67%      -76%        -80%      -90%          -91%
Opt Perl      106157/s      201%       --      -27%        -39%      -71%          -74%
Hash Perl     146056/s      314%      38%        --        -16%      -60%          -65%
Lookup Perl   174216/s      394%      64%       19%          --      -52%          -58%
Inline::C     363196/s      929%     242%      149%        108%        --          -12%
Opt Inline::C 412088/s     1068%     288%      182%        137%       13%            --
