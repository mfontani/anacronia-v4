package Av4::Ansi;
use strict;
use warnings;

use Inline C  => <<'END_INLINE_C';
    unsigned char __colors[8] = "xrgybpcw";
    unsigned char getcolor(unsigned char clrchar) {
        char i = 0;
        for ( i = 0; i < 8; i++ ) {
            if (   clrchar     == __colors[i] ) { return i; }
            if ( ( clrchar+32) == __colors[i] ) { return i; }
        }
        return (unsigned char) -1;
    }
END_INLINE_C

our ( $amp, $car, $bang ) = (ord('&'), ord('^'),ord('!'));

sub ansify {
    my $string    = shift;
    my $status    = shift;
    my $gotstatus = defined $status ? 1 : 0;
    my $out       = '';
    if ( !defined $status ) {
        $out    = "\e[0m";
        $status = {};
    }

    # sane defaults:
    $status->{cmdfound}  = 0     if ( !defined $status->{cmdfound} );
    $status->{prevfg}    = 39    if ( !defined $status->{prevfg} );
    $status->{prevbg}    = 49    if ( !defined $status->{prevbg} );
    $status->{prevbold}  = '22;' if ( !defined $status->{prevbold} );
    $status->{prevblink} = ''    if ( !defined $status->{prevblink} );
    my ( $newfg, $newbg, $newbold ) = ( $status->{prevfg}, $status->{prevbg}, $status->{prevbold} );

    my @str = unpack('C*',$string);
    foreach my $i ( 0 .. $#str ) {
        if ( !$status->{cmdfound} ) {    # previous character wasn't a control charaacter
            if ( $str[$i] != $amp && $str[$i] != $car ) {
                $out .= chr $str[$i];
                next;
            }                            # normal character => copy as is
            $status->{cmdfound} = $str[$i];    # got control character
            next;
        }

        # previous character was control character
        # same character if repeated 2 times: && for &, ^^ for ^
        if ( $status->{cmdfound} == $amp && $str[$i] == $amp ) {
            $out .= '&';
            $status->{cmdfound} = 0;
            next;
        }
        if ( $status->{cmdfound} == $car && $str[$i] == $car ) {
            $out .= '^';
            $status->{cmdfound} = 0;
            next;
        }

        # colours resets
        # &! resets foreground and bold, ^! resets background and bold, &^ and ^& resets all
        if ( $status->{cmdfound} == $amp && $str[$i] == $bang ) {
            if   ( $newbold eq '1;' ) { $out .= "\e[22;39m"; }
            else                      { $out .= "\e[39m"; }
            $status->{prevbold} = '22;';
            $newbold            = '22;';
            $newfg              = 39;
            $status->{prevfg}   = 39;
            $status->{cmdfound} = 0;
            next;
        }
        if ( $status->{cmdfound} == $car && $str[$i] == $bang ) {
            if   ( $newbold eq '1;' ) { $out .= "\e[22;49m"; }
            else                      { $out .= "\e[49m"; }
            $status->{prevbold} = '22;';
            $newbold            = '22;';
            $newbg              = 49;
            $status->{prevbg}   = 49;
            $status->{cmdfound} = 0;
            next;
        }
        if (   ( $status->{cmdfound} == $car && $str[$i] == $amp )
            || ( $status->{cmdfound} == $amp && $str[$i] == $car ) )
        {
            $out .= "\e[0m";
            $status->{prevfg}    = 39;
            $newfg               = 39;
            $status->{prevbg}    = 49;
            $newbg               = 49;
            $status->{prevbold}  = '22;';
            $newbold             = '22;';
            $status->{prevblink} = '';
            $status->{cmdfound}  = 0;
            next;
        }

        # bail in case the color character isn't recognised
        my $newcol = getcolor( $str[$i] );
        if ( $newcol >= 255 ) { $status->{cmdfound} = 0; next }    # TODO: handle blink?

        if ( $status->{cmdfound} == $amp ) {                     # foreground
            $status->{prevfg} = $newfg;
            $newfg = 30 + $newcol;
        } else { #  ( $status->{cmdfound} == $car ) {                # background
            $status->{prevbg} = $newbg;
            $newbg = 40 + $newcol;
        }
        if ( $str[$i] >= 65 && $str[$i] < 97) {                     # uppercase, bold
            $status->{prevbold} = $newbold;
            $newbold = '1;';
        } else {
            $status->{prevbold} = $newbold;
            $newbold = '22;';
        }
        my $ln = sprintf(
            "\033[%s%s%s",
            $status->{prevbold} ne $newbold ? $newbold : '',

            #$status->{prevblink} ne $newblink ? $newblink : '', # TODO: blink
            $status->{prevfg} ne $newfg ? $newfg . ';' : '',
            $status->{prevbg} ne $newbg ? $newbg . ';' : '',
        );
        $ln =~ s/;$/m/;
        $out .= $ln;
        $status->{cmdfound} = 0;
        $status->{prevbg}   = $newbg;
        $status->{prevfg}   = $newfg;
        $status->{prevbold} = $newbold;
    }
    my $out2 = $out;
    chomp($out2);
    if ( $out2 ne $out ) {    # newline needs added at end
        $out = $out2 . "\033[0m\n\r";
    } else {

        #$out = $out2 . "\033[0m";
    }
    return $gotstatus ? ( $status, $out ) : $out;
}

1;

__END__

## Benchmarks (Devel::NYTProf) for getcolor():
# with chr:
# 34533   98.9ms  34533   457ms           my $newcol = getcolor( chr $str[$i] );
#         # spent   457ms making 34533 calls to Av4::Ansi::getcolor, avg 13µs/call
# 
# with ord:
# 23719   71.8ms  23719   303ms           my $newcol = getcolor( $str[$i] );
#         # spent   303ms making 23719 calls to Av4::Ansi::getcolor, avg 13µs/call
# 
# with inline::c:
# 16750   73.8ms  16750   25.1ms          my $newcol = __getcolor( $str[$i] );
#         # spent  25.1ms making 16750 calls to Av4::Ansi::__getcolor, avg 1µs/call
