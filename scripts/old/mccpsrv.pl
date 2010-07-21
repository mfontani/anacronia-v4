#!/usr/bin/perl
use warnings;
use strict;
use POSIX;
use IO::Socket;
use POE;
use Compress::Zlib;
use Text::Lorem;

POE::Session->create(
    inline_states => {
        _start       => \&server_start,
        event_accept => \&server_accept,
        event_read   => \&client_read,
        event_write  => \&client_write,
        event_error  => \&client_error,
    }
);
my %inbuffer  = ();
my %outbuffer = ();
my $LOREM     = Text::Lorem->new;

sub server_start {
    my $server = IO::Socket::INET->new(
        LocalPort => 12345,
        Listen    => 10,
        Reuse     => "yes",
    ) or die "can't make server socket: $@\n";
    $_[KERNEL]->select_read( $server, "event_accept" );
}

sub server_accept {
    my ( $kernel, $server ) = @_[ KERNEL, ARG0 ];
    my $new_client = $server->accept();
    my $rv;
    $rv = $new_client->send( "Hi!\r\n", 0 );
    if ( !defined $rv ) { warn "Cant send()\n"; return }
    $rv = $new_client->send(
        sprintf( "%c%c%c\r\n", 255, 251, 86 ),    #IAC WILL COMPRESS2
        0
    );
    if ( !defined $rv ) { warn "Cant send()\n"; return }
    $kernel->select_read( $new_client, "event_read" );
}

my %TELOPTS = (
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

my %TELOPTIONS = (
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
    86  => 'COMPRESS2',
);

sub analyze_data {
    my ( $data, $sock, $heap ) = @_;
    my $iac     = 0;    # default state
    my $do      = -1;
    my $newdata = '';
    foreach my $char ( split( '', $data ) ) {
        print "$char (",
          "dec ", sprintf( "%d", ord $char ),
          " hex ", sprintf( "%x", ord $char ), ' ';
        if ( $iac == 0 ) {    # only IAC or standard characters allowed
            if ( ord $char == 255 ) {    # IAC
                $iac = 1;
                print "!IAC\n";
                next;
            } elsif ( ord $char > 240 ) {
                print "Shouldnt have received this (!IAC, >240)";
            }
            $newdata .= $char;
            print "\n";
            next;
        }
        if ( $iac == 1 ) {               # Got IAC, waiting on DO/DONT, etc
            if ( ord $char < 240 ) {
                print "Shouldnt have received this (IAC=1, <240)";
            } elsif ( defined $TELOPTS{ ord $char } ) {
                if ( ord $char >= 251 && ord $char <= 254 ) {
                    $iac = 2;
                    print "++";
                    if ( ord $char == 253 ) {    # DO
                        $do = 1;
                    }
                }
                print $TELOPTS{ ord $char }, "\n";
                next;
            }
            $newdata .= $char;
            print "\n";
            next;
        }
        if ( $iac == 2 ) {                       # Got IAC DO/DONT, waiting on option
            if ( defined $TELOPTIONS{ ord $char } ) {
                print $TELOPTIONS{ ord $char }, '!';
                $iac = 0;
                if ( $do == 1 ) {
                    print " => IAC DO!!";
                    if ( ord $char == 86 ) {

                        # Send IAC SB COMPRESS2 IAC SE ?
                        $heap->{mccp} = 1;
                        print " OK COMPRESS2 STARTS";
                    }
                }
                $do = -1;
            } else {
                print "unknown option";
            }
            print "\n";
            next;
        }
        die "help!";
    }
    return $newdata;
}

sub client_read {
    my ( $kernel, $client ) = @_[ KERNEL, ARG0 ];
    my $data = "";
    my $rv = $client->recv( $data, POSIX::BUFSIZ, 0 );
    unless ( defined($rv) and length($data) ) {
        $kernel->yield( event_error => $client );
        return;
    }
    $data = analyze_data( $data, $client, $_[HEAP] );
    $inbuffer{$client} .= $data;
    while ( $inbuffer{$client} =~ s/(.*\n)// ) {
        $outbuffer{$client} .= $1;
    }
    if ( exists $outbuffer{$client} ) {
        $kernel->select_write( $client, "event_write" );
    }
}

my $data_sent    = 0;
my $nonmccp_sent = 0;
my $mccp_sent    = 0;

sub client_write {
    my ( $kernel, $client ) = @_[ KERNEL, ARG0 ];
    unless ( exists $outbuffer{$client} ) {
        $kernel->select_write($client);
        return;
    }
    $outbuffer{$client} .= $LOREM->paragraphs( int rand(5) + 3 );
    print "Sending via ", defined $_[HEAP]->{mccp} ? 'MCCP' : 'TEXT', "\n";
    my $IACSBCOMPRESS2IACSE = sprintf( "%c%c%c%c%c", 255, 250, 86, 255, 240 );
    my $data =
      defined $_[HEAP]->{mccp}
      ? $IACSBCOMPRESS2IACSE . compress( $outbuffer{$client} )
      : $outbuffer{$client};
    my $datalength = length $data;
    my $origlength = length $outbuffer{$client};
    $data_sent += $origlength;

    if ( defined $_[HEAP]->{mccp} ) {
        $mccp_sent += $datalength;
    } else {
        $nonmccp_sent += $datalength;
    }
    print "stats: ",
      "total sent $data_sent, non-mccp: $nonmccp_sent, mccp: $mccp_sent; ",
      $mccp_sent * 100 / $data_sent,    "% mccp data; ",
      $nonmccp_sent * 100 / $data_sent, "% nonmccp data\n";
    my $rv = $client->send( $data, 0 );
    unless ( defined $rv ) {
        warn "Cant send()\n";
        return;
    }
    if (   $rv == $datalength
        or $! == POSIX::EWOULDBLOCK )
    {

        #substr( $outbuffer{$client}, 0, $rv ) = "";
        #delete $outbuffer{$client} unless length $outbuffer{$client};
        delete $outbuffer{$client};
        return;
    }
    $kernel->yield( event_error => $client );
}

sub client_error {
    my ( $kernel, $client ) = @_[ KERNEL, ARG0 ];
    delete $inbuffer{$client};
    delete $outbuffer{$client};
    $kernel->select($client);
    close $client;
}
POE::Kernel->run();
exit;
