package Av4::Telnet;
use strict;
use warnings;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
  %TELOPTS %TELOPTIONS
  TELOPT_FIRST
  TELOPT_WILL TELOPT_WONT
  TELOPT_DO TELOPT_DONT
  TELOPT_IAC TELOPT_SB TELOPT_SE
  TELOPT_COMPRESS2 TELOPT_MSP TELOPT_MXP
  TELOPT_TTYPE TELOPT_NAWS
  TELOPT_GA
  _256col
);

use constant TELOPT_FIRST     => 240;
use constant TELOPT_WILL      => 251;
use constant TELOPT_WONT      => 252;
use constant TELOPT_DO        => 253;
use constant TELOPT_DONT      => 254;
use constant TELOPT_IAC       => 255;
use constant TELOPT_COMPRESS2 => 86;
use constant TELOPT_TTYPE     => 24;
use constant TELOPT_NAWS      => 31;
use constant TELOPT_MSP       => 90;
use constant TELOPT_MXP       => 91;
use constant TELOPT_SB        => 250;
use constant TELOPT_SE        => 240;
use constant TELOPT_GA        => 249;

our %TELOPTS = (
    240 => 'SE',
    241 => 'NOP',
    242 => 'DATAMARK',
    243 => 'BREAK',
    244 => 'IP',
    245 => 'AO',
    246 => 'AYT',
    247 => 'EC',
    248 => 'EL',
    249 => 'GA',
    250 => 'SB',
    251 => 'WILL',
    252 => 'WONT',
    253 => 'DO',
    254 => 'DONT',
    255 => 'IAC',
);

our %TELOPTIONS = (
    0   => 'BINARY',
    1   => 'ECHO',
    2   => 'RCP',
    3   => 'SGA',
    4   => 'NAMS',
    5   => 'STATUS',
    6   => 'TM',
    7   => 'RCTE',
    8   => 'NAOL',
    9   => 'NAOP',
    10  => 'NAOCRD',
    11  => 'NAOHTS',
    12  => 'NAOHTD',
    13  => 'NAOFFD',
    14  => 'NAOVTS',
    15  => 'NAOVTD',
    16  => 'NAOLFD',
    17  => 'XASCII',
    18  => 'LOGOUT',
    19  => 'BM',
    20  => 'DET',
    21  => 'SUPDUP',
    22  => 'SUPDUPOUTPUT',
    23  => 'SNDLOC',
    24  => 'TTYPE',
    25  => 'EOR',
    26  => 'TUID',
    27  => 'OUTMRK',
    28  => 'TTYLOC',
    29  => '3270REGIME',
    30  => 'X3PAD',
    31  => 'NAWS',
    32  => 'TSPEED',
    33  => 'LFLOW',
    34  => 'LINEMODE',
    35  => 'XDISPLOC',
    36  => 'OLD_ENVIRON',
    37  => 'AUTHENTICATION',
    38  => 'ENCRYPT',
    39  => 'NEW_ENVIRON',
    255 => 'EXOPL',
    85  => 'COMPRESS',
    86  => 'COMPRESS2',        # http://www.zuggsoft.com/zmud/mcp.htm
    90  => 'MSP',              # http://www.zuggsoft.com/zmud/msp.htm
    91  => 'MXP',              # http://www.zuggsoft.com/zmud/mxp.htm
                               # http://www.moo.mud.org/mcp/mcp2.html
                               # http://www.zuggsoft.com/zmud/mcp-dev.htm
);

my $_256col;

sub _256col {
    return $_256col if defined $_256col;
    my $out = '';
    $out .= "System colors:\r\n";
    for ( my $color = 0 ; $color < 8 ; $color++ ) {
        $out .= sprintf "\x1b[48;5;${color}m  ";
    }
    $out .= "\x1b[0m\r\n";

    # this one kills kildclient
    #for ( my $color = 8 ; $color < 16 ; $color++ ) {
    #    $out .= sprintf "\x1b[48;5;${color}m  ";
    #}

    $out .= sprintf "\x1b[0m\r\n\r\n";

    # now the color cube
    $out .= sprintf "Color cube, 6x6x6:\r\n";
    for ( my $green = 0 ; $green < 6 ; $green++ ) {
        for ( my $red = 0 ; $red < 6 ; $red++ ) {
            for ( my $blue = 0 ; $blue < 6 ; $blue++ ) {
                my $color = 16 + ( $red * 36 ) + ( $green * 6 ) + $blue;
                $out .= sprintf "\x1b[48;5;${color}m  ";
            }
            $out .= sprintf "\x1b[0m ";
        }
        $out .= sprintf "\r\n";
    }

    # now the grayscale ramp
    $out .= sprintf "Grayscale ramp:\r\n";
    for ( my $color = 232 ; $color < 256 ; $color++ ) {
        $out .= sprintf "\x1b[48;5;${color}m  ";
    }
    $out .= sprintf "\x1b[0m\r\n";
    $out .= "\r\n\r\n";
    $_256col = $out;
    return $out;
}

1;
