#!/usr/bin/env perl
use strict;
use warnings;
use Test::More qw/no_plan/;

BEGIN {
    use_ok( 'Av4::Ansi' );
}

can_ok ('Av4::Ansi', qw/getcolor ansify/);

####### getcolor

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

# xrgybpcw
# 01234567
{
    my %colchars = (qw/x 0 r 1 g 2 y 3 b 4 p 5 c 6 w 7/);
    foreach (qw/x r g y b p c w/) {
        my $x = Av4::Ansi::getcolor( ord $_ );
        ok( $x == $colchars{$_}, $_ . ' ansi == ' . $colchars{$_} ) or diag("$_ expected $colchars{$_} got $x");
        $x = Av4::Ansi::getcolor( ord uc $_ );
        ok( $x == $colchars{$_}, uc($_) . ' ansi == ' . $colchars{$_} ) or diag("$_ expected $colchars{$_} got $x");
        $x = perl_getcolor( ord $_ );
        ok( $x == $colchars{$_}, $_ . ' ansi == ' . $colchars{$_} ) or diag("(perl) $_ expected $colchars{$_} got $x");
        $x = Av4::Ansi::getcolor( ord uc $_ );
        ok( $x == $colchars{$_}, uc($_) . ' ansi == ' . $colchars{$_} ) or diag("(perl) $_ expected $colchars{$_} got $x");
    }
    for (my $ord = ord 'A'; $ord <= ord 'z'; $ord++) {
        my $x = Av4::Ansi::getcolor( $ord );
        my $y = perl_getcolor( $ord );
        is($x,$y,"Char $ord (" . chr($ord) . ") same for Inline::C and Pure Perl");
    }
}

sub testansified {
    my ($str,$desired) = @_;
    my $ansified = Av4::Ansi::ansify($str);
    my $readableansified = $ansified;
    my $readabledesired = $desired;
    $readableansified =~ s/\e/E/g;
    $readabledesired =~ s/\e/E/g;
    $readableansified =~ s/\n/\\N/g;
    $readabledesired =~ s/\n/\\N/g;
    $readableansified =~ s/\r/\\R/g;
    $readabledesired =~ s/\r/\\R/g;
    ok(
        $ansified eq $desired,
        'ansify ~' . $str . '~ == ~' . $readabledesired . '~: ~' . $ansified . '~'
    ) or diag ("Ansify $str gave back ~$readableansified~");
}


## FOREGROUNDS ONLY
# ok:
testansified('&xx',"\e[0m\e[30mx");
testansified('&rx',"\e[0m\e[31mx");
testansified('&gx',"\e[0m\e[32mx");
testansified('&yx',"\e[0m\e[33mx");
testansified('&bx',"\e[0m\e[34mx");
testansified('&px',"\e[0m\e[35mx");
testansified('&cx',"\e[0m\e[36mx");
testansified('&wx',"\e[0m\e[37mx");

testansified('&Xx',"\e[0m\e[1;30mx");
testansified('&Rx',"\e[0m\e[1;31mx");
testansified('&Gx',"\e[0m\e[1;32mx");
testansified('&Yx',"\e[0m\e[1;33mx");
testansified('&Bx',"\e[0m\e[1;34mx");
testansified('&Px',"\e[0m\e[1;35mx");
testansified('&Cx',"\e[0m\e[1;36mx");
testansified('&Wx',"\e[0m\e[1;37mx");

testansified('&xx&rr&gg&yy',"\e[0m\e[30mx\e[31mr\e[32mg\e[33my");
testansified('&xx&Rr&Gg&yy',"\e[0m\e[30mx\e[1;31mr\e[32mg\e[22;33my");

## BACKGROUNDS ONLY
# ok:
testansified('^xx',"\e[0m\e[40mx");
testansified('^rx',"\e[0m\e[41mx");
testansified('^gx',"\e[0m\e[42mx");
testansified('^yx',"\e[0m\e[43mx");
testansified('^bx',"\e[0m\e[44mx");
testansified('^px',"\e[0m\e[45mx");
testansified('^cx',"\e[0m\e[46mx");
testansified('^wx',"\e[0m\e[47mx");

testansified('^Xx',"\e[0m\e[1;40mx");
testansified('^Rx',"\e[0m\e[1;41mx");
testansified('^Gx',"\e[0m\e[1;42mx");
testansified('^Yx',"\e[0m\e[1;43mx");
testansified('^Bx',"\e[0m\e[1;44mx");
testansified('^Px',"\e[0m\e[1;45mx");
testansified('^Cx',"\e[0m\e[1;46mx");
testansified('^Wx',"\e[0m\e[1;47mx");

testansified('^xx^rr^gg^yy',"\e[0m\e[40mx\e[41mr\e[42mg\e[43my");

## FOREGROUND BACKGROUND
# ok:
testansified('&rr^yry',"\e[0m\e[31mr\e[43mry");
testansified('&rr^yry&gg',"\e[0m\e[31mr\e[43mry\e[32mg");
testansified('^rr&yy',"\e[0m\e[41mr\e[33my");
testansified('^rr&YY&yy',"\e[0m\e[41mr\e[1;33mY\e[22my");
testansified('^rr&YY&py',"\e[0m\e[41mr\e[1;33mY\e[22;35my");

## Colours resets
testansified("&rred&!nothing","\e[0m\e[31mred\e[39mnothing");
testansified("&Rred&!nothing","\e[0m\e[1;31mred\e[22;39mnothing");
testansified("^rred^!nothing","\e[0m\e[41mred\e[49mnothing");
testansified("^Rred^!nothing","\e[0m\e[1;41mred\e[22;49mnothing");
testansified("^rred^!&rred","\e[0m\e[41mred\e[49m\e[31mred");
testansified("^Rred^!&rred","\e[0m\e[1;41mred\e[22;49m\e[31mred");
testansified("&rred&!^rred","\e[0m\e[31mred\e[39m\e[41mred");
testansified("&rred^yyellow&^nothing","\e[0m\e[31mred\e[43myellow\e[0mnothing");
testansified("&rred^yyellow^&nothing","\e[0m\e[31mred\e[43myellow\e[0mnothing");
testansified("&rred^yyellow&^&ggreen","\e[0m\e[31mred\e[43myellow\e[0m\e[32mgreen");
testansified("&rred^yyellow^&^ggreen","\e[0m\e[31mred\e[43myellow\e[0m\e[42mgreen");

# full branch coverage
testansified( "&rred&&red",     "\e[0m\e[31mred&red" );        # 50   50  T   F   if ($$status{'cmdfound'} == $amp and $str[$i] == $amp)
testansified( "^rred^^nothing", "\e[0m\e[41mred^nothing" );    # 55   50  T   F   if ($$status{'cmdfound'} == $car and $str[$i] == $car)
testansified( "^0nothing",      "\e[0mnothing" );              # 100    50  T   F   if ($newcol >= 255)
testansified( "^0nothing\n",    "\e[0mnothing\e[0m\n\r" );     # 133    100 T   F   if ($out2 ne $out) { }
testansified( "^rred^yyellow",  "\e[0m\e[41mred\e[43myellow" );    # 50 T   F   elsif ($$status{'cmdfound'} == $car) { }
#  09  67  $str[$i] >= 65 and $str[$i] < 97   #### ???
#  A   B   dec
#  0   X   0
#  1   0   0
#  1   1   1
### none of the below match it..
testansified( "^Yabc", "\e[0m\e[1;43mabc" );
testansified( "^Yabc^rabc^?def", "\e[0m\e[1;43mabc\e[22;41mabcdef" );
testansified( "^Yabc^Rabc^?def", "\e[0m\e[1;43mabc\e[41mabcdef" );
testansified( "^Yabc^Rabc", "\e[0m\e[1;43mabc\e[41mabc" );

## MULTIPLE CALLS
sub testmultipleansified {
    my ($astr,$desired) = @_;
    my @str = @{$astr};
    my $ansified = '';
    my $status = {};
    foreach my $str (@str) {
        my $justansified;
        ($status,$justansified) = Av4::Ansi::ansify($str,$status);
        ok (ref $status eq 'HASH', 'ansify returns hash if given status hash');
        ok (ref $justansified eq '', 'ansify returns str if given status hash');
        ok (defined $justansified, 'ansify returns defined str if given status hash');
        $ansified .= $justansified;
    }
    my $readableansified = $ansified;
    my $readabledesired = $desired;
    $readableansified =~ s/\e/E/g;
    $readabledesired =~ s/\e/E/g;
    ok(
        $ansified eq $desired,
        "ansify @str == $readabledesired : $ansified"
    ) or diag ("Ansify @str == $readableansified");
}
testmultipleansified(["test 123 ","&rred","&!test 345"],"test 123 \e[31mred\e[39mtest 345");
testmultipleansified(["test 123 ","&Rred","&!test 345"],"test 123 \e[1;31mred\e[22;39mtest 345");
