package Av4::TelnetOptions;
use strict;
use warnings;
use Av4::User;
use Compress::Zlib;
use Av4::Utils qw/get_logger ansify/;
use Av4::Telnet qw/
  %TELOPTS %TELOPTIONS
  TELOPT_FIRST
  TELOPT_WILL TELOPT_WONT
  TELOPT_DO TELOPT_DONT
  TELOPT_IAC TELOPT_SB TELOPT_SE
  TELOPT_COMPRESS2
  TELOPT_TTYPE TELOPT_NAWS
  TELOPT_MXP
  _256col
  /;

sub DEBUGTELNETOPTS { 1 }

use Class::XSAccessor {
    constructor => '_new',
    accessors => [qw/user mccp terminaltype naws_w naws_h
        state_iac state_do state_sb state_will mxp
        state_got_ttype state_ttype state_got_naws state_naws zstream/],
};

sub new {
    my $class = shift;
    $class->_new(
        # defaults
        user => '',
        mccp => 0,
        mxp => 0,
        terminaltype => 'undefined',
        naws_w => 0,
        naws_h => 0,
        state_iac => 0,
        state_do => -1,
        state_sb => -1,
        state_will => 1,
        state_got_ttype => 0,
        state_ttype => '',
        state_got_naws => 0,
        state_naws => [],
        zstream => 0,
        # wanted options
        @_,
    );
}

sub send_data {
    my $self   = shift;
    my $out    = shift;
    my $lenout = length $$out;
    my $log  = get_logger();
    if ( !$self->mccp ) {
        #$log->trace( "Sending data to client ", $self->user, " via plain text" );
        $Av4::mud_chars_sent         += $lenout;
        $Av4::mud_chars_sent_nonmccp += $lenout;
        $Av4::mud_data_sent          += $lenout;
        $Av4::mud_data_sent_nonmccp  += $lenout;
        #$self->user->server->outbuffer->{ $self->user->id } .= $$out;
        $self->user->id->push_write($$out);
        return;
    }
    if ( !$self->zstream ) {
        $log->error( "Client ", $self->user, " has MCCP enabled but no zstream!" );
        $self->user->server->kernel->yield( event_error => $self->user->id );
        return;
    }
    my ( $outdeflate, $deflatestatus ) = $self->zstream->deflate($$out);
    if ( !defined $outdeflate ) {
        $log->error( "Client ", $self->user, ": undefined deflate: status ", $deflatestatus );
        $self->user->server->kernel->yield( event_error => $self->user->id );
        return;
    }
    #$log->trace(
    #    "Client ", $self->user,
    #    " via mccp, deflated is ",
    #    length $outdeflate,
    #    "; added to buffer!"
    #);
    $Av4::mud_chars_sent      += $lenout;
    $Av4::mud_chars_sent_mccp += $lenout;
    $Av4::mud_data_sent       += length $outdeflate;
    $Av4::mud_data_sent_mccp  += length $outdeflate;
    #$self->user->server->outbuffer->{ $self->user->id } .= $outdeflate;
    $self->user->id->push_write($outdeflate);
    my ( $outflush, $flushstatus ) = $self->zstream->flush(Z_SYNC_FLUSH);
    if ( !defined $outflush ) {
        $log->error( "Client ", $self->user, ": undefined flush: status ", $flushstatus );
        $self->user->server->kernel->yield( event_error => $self->user->id );
        return;
    }
    $log->debug(
        "Client ", $self->user,
        " via mccp, flushed is ",
        length $outflush,
        "; added to buffer!"
    );
    $Av4::mud_data_sent      += length $outflush;
    $Av4::mud_data_sent_mccp += length $outflush;
    $self->user->server->outbuffer->{ $self->user->id } .= $outflush;
    $self->user->id->push_write($outflush);
    #$self->user->server->kernel->select_write( $self->user->id, 'event_write' );
}

sub mccp2start {
    my $self = shift;
    my $log  = get_logger();
    $log->info( "Sending IAC SB COMPRESS2 IAC SE to client ", $self->user );
    $self->user->id->push_write( sprintf(
        "%c%c%c%c%c", 255, 250, 86, 255, 240    # IAC SB COMPRESS2 IAC SE
    ));
    $log->info( "Creating ZStream for client ", $self->user );
    my ( $d, $initstatus ) = deflateInit( -Level => Z_BEST_COMPRESSION );
    if ( !defined $d ) {
        $log->error( "Client ", $self->user, ": undefined deflateInit: status ", $initstatus );
        $self->user->server->kernel->yield( event_error => $self->user->id );
        return;
    }
    $self->zstream($d);
    $self->mccp(1);
    $log->info( "MCCP==1 now for client ", $self->user );
}

sub mccp2end {
    my $self = shift;
    my $log  = get_logger();
    $log->info( "Client ", $self->user, " wants to end compression" );
    if ( !$self->mccp ) {
        $log->info( "Client ", $self->user,
            " wants to end compression => doesnt have MCCP enable, exiting" );
        return;
    }
    $self->zstream(0);
    $self->mccp(0);
    $log->info( "MCCP==0 now for client ", $self->user );
}

## does thet telnet magic
sub analyze {
    my ( $self, $data ) = @_;
    my $newdata = '';
    my $log     = get_logger();
    $log->debug( "_analyze_data: str length ", length $data ) if DEBUGTELNETOPTS;
    my $charno = 0;

    foreach my $char ( split( '', $data ) ) {
        $log->debug(
            "$charno) Got character: ",
            "dec ", sprintf( "%d", ord $char ),
            " hex ", sprintf( "%x", ord $char ), ' '
        ) if DEBUGTELNETOPTS;
        $charno++;
        if ( $self->state_iac == 0 ) {    # only IAC or standard characters allowed
            $log->trace('$iac == 0') if DEBUGTELNETOPTS;
            if ( ord $char == TELOPT_IAC ) {
                $self->state_iac(1);
                $log->debug("IAC\n") if DEBUGTELNETOPTS;
                next;
            } elsif ( ord $char >= TELOPT_FIRST ) {
                $log->warn( "Client ", $self->user, ": shouldn't have received this (!IAC, >240)" );
                die "&RGarbage character received; Closing connection\r\n";
            }
            $newdata .= $char;
            next;
        } elsif ( $self->state_iac == 1 ) {    # Got IAC, waiting on DO/DONT, etc
            $log->trace('$iac == 1') if DEBUGTELNETOPTS;
            if ( ord $char < TELOPT_FIRST ) {
                $log->warn( "Client ", $self->user,
                    ": shouldn't have received this (IAC=1, <240)" );
                die "&RGarbage character received; Closing connection\r\n";
            } elsif ( defined $TELOPTS{ ord $char } ) {
                if ( ( ord $char >= TELOPT_WILL && ord $char <= TELOPT_DONT )
                    || ord $char == TELOPT_SB )
                {
                    $self->state_iac(2);
                    if ( ord $char == TELOPT_DO ) {
                        $self->state_do(1);
                    } elsif ( ord $char == TELOPT_DONT ) {
                        $self->state_do(0);
                    } elsif ( ord $char == TELOPT_WILL ) {
                        $self->state_will(1);
                    } elsif ( ord $char == TELOPT_WONT ) {
                        $self->state_will(0);
                    } elsif ( ord $char == TELOPT_SB ) {
                        $self->state_sb(1);
                    }
                }
                $log->debug( $TELOPTS{ ord $char }, "\n" ) if DEBUGTELNETOPTS;
                next;
            }
            $newdata .= $char;
            next;
        } elsif ( $self->state_iac == 2 ) {    # Got IAC DO/DONT/WILL/WONT/SB, waiting on option
            $log->trace('$iac == 2') if DEBUGTELNETOPTS;
            if ( defined $TELOPTIONS{ ord $char } ) {
                $log->debug( $TELOPTIONS{ ord $char }, '!' ) if DEBUGTELNETOPTS;
                if ( $self->state_do == 1 ) {
                    $log->debug(" => IAC DO!!") if DEBUGTELNETOPTS;
                    if ( ord $char == TELOPT_COMPRESS2 ) {
                        $self->mccp2start();
                        $log->info( "Client ", $self->user, " OK COMPRESS2 STARTS" ) if DEBUGTELNETOPTS;
                    } elsif ( ord $char == TELOPT_MXP ) {
                        $log->info( "Client ", $self->user, " OK MXP STARTS" ) if DEBUGTELNETOPTS;
                        $self->user->print( sprintf(
                            "%c%c%c%c%c", 255, 250, TELOPT_MXP, 255, 240    # IAC SB MXP IAC SE
                        ));
                        $self->user->print( "\e[7z" ); # lock locked mode
                        $self->mxp(1);
                    }
                } elsif ( $self->state_do == 0 ) {
                    $log->debug( " => IAC DONT ", $TELOPTIONS{ ord $char } ) if DEBUGTELNETOPTS;
                    if ( ord $char == TELOPT_COMPRESS2 ) {
                        $self->mccp2end();
                        $log->info( "Client ", $self->user, "OK COMPRESS2 STOP" ) if DEBUGTELNETOPTS;
                    } elsif ( ord $char == TELOPT_MXP ) {
                        $self->mxp(0);
                        $log->info( "Client ", $self->user, "OK MXP STOP" ) if DEBUGTELNETOPTS;
                    }
                } elsif ( $self->state_will == 1 ) {
                    $log->debug(" => IAC WILL!!") if DEBUGTELNETOPTS;
                    if ( ord $char == TELOPT_TTYPE ) {
                        $log->info( "Client ", $self->user, " CAN DO TTYPE" ) if DEBUGTELNETOPTS;
                        $self->user->print(
                            sprintf( "%c%c%c%c%c%c",
                                TELOPT_IAC, TELOPT_SB, TELOPT_TTYPE, 1, TELOPT_IAC, TELOPT_SE, )
                        );

                        # TODO multiple terminal types
                    } elsif ( ord $char == TELOPT_NAWS ) {
                        $log->debug( "Client ", $self->user, " CAN DO NAWS" ) if DEBUGTELNETOPTS;
                    }
                } elsif ( $self->state_will == 0 ) {
                    $log->debug( " => IAC WONT ", $TELOPTIONS{ ord $char } ) if DEBUGTELNETOPTS;
                } elsif ( $self->state_sb == 1 ) {
                    $log->debug(" => IAC SB!!") if DEBUGTELNETOPTS;
                    if ( ord $char == TELOPT_TTYPE ) {
                        $log->debug( "Client ", $self->user, " SB TTYPE" ) if DEBUGTELNETOPTS;
                        $self->state_got_ttype(1);
                        $self->state_ttype('');
                        $self->state_sb(2);
                    } elsif ( ord $char == TELOPT_NAWS ) {
                        $log->debug( "Client ", $self->user, " SB NAWS" ) if DEBUGTELNETOPTS;
                        $self->state_got_naws(1);
                        $self->state_naws( [] );
                        $self->state_sb(2);
                    }
                    $self->state_iac(3);
                    next;
                }
            } else {
                $log->info( "Client ", $self->user, " unknown telnet option ", ord $char );
            }
            $self->state_will(-1);
            $self->state_do(-1);
            $self->state_iac(0);
            next;
        } elsif ( $self->state_iac == 3 ) {    # Got IAC SB ...
            $log->trace('$iac == 3') if DEBUGTELNETOPTS;
            if ( $self->state_sb == 2 ) {      # Got IAC SB OPTION, waiting on DATA
                if ( $self->state_got_ttype ) {
                    if ( ord $char == 0 ) {
                        $log->debug(' => IAC SB TTYPE 0!') if DEBUGTELNETOPTS;
                        $self->state_sb(3);
                    } else {
                        $log->debug(' => IAC SB TTYPE ??') if DEBUGTELNETOPTS;
                        $self->state_sb(3);
                    }
                } elsif ( $self->state_got_naws ) {
                    $log->debug( "Got char for NAWS: ", sprintf( "%d", ord $char ) ) if DEBUGTELNETOPTS;
                    push @{ $self->state_naws }, ord $char;
                    if ( @{ $self->state_naws } == 4 ) {
                        $log->debug("NAWS received 4 scalars, awaiting IAC") if DEBUGTELNETOPTS;
                        $self->state_sb(3);
                    }
                } else {
                    $log->debug(' => IAC SB UNKNOWN awaiting IAC') if DEBUGTELNETOPTS;
                }
            } elsif ( $self->state_sb == 3 ) {    # got IAC SB OPTION DATA, waiting on IAC
                if ( $self->state_got_ttype ) {
                    if ( ord $char == TELOPT_IAC ) {
                        $log->debug(' => IAC SB TTYPE DATA [..] IAC!') if DEBUGTELNETOPTS;
                        $self->state_sb(4);
                    } else {
                        $log->debug( ' => IAC SB TTYPE DATA newchar: ', $char ) if DEBUGTELNETOPTS;
                        $self->state_ttype( $self->state_ttype . $char );
                    }
                } elsif ( $self->state_got_naws ) {
                    if ( ord $char == TELOPT_IAC ) {
                        $log->debug(' => IAC SB NAWS [..] IAC!') if DEBUGTELNETOPTS;
                        $self->state_sb(4);
                    } else {
                        $log->debug( ' => IAC SB NAWS unknown char: ', $char ) if DEBUGTELNETOPTS;
                        #$ttype .= $char;
                    }
                } else {
                    $log->debug(' => IAC SB UNKNOWN awaiting IAC') if DEBUGTELNETOPTS;
                }
            } elsif ( $self->state_sb == 4 ) {    # Got IAC SB OPTION DATA IAC, waiting on SE
                if ( ord $char == TELOPT_SE ) {
                    $log->debug(' => IAC SB OPTION DATA IAC SE!') if DEBUGTELNETOPTS;
                    if ( $self->state_got_ttype ) {
                        $log->debug( 'GOT TTYPE: >', $self->state_ttype, '<' ) if DEBUGTELNETOPTS;
                        #$self->user->print( 'Your terminal type is:', $self->state_ttype, "\r\n" ) if DEBUGTELNETOPTS;
                        $self->terminaltype( $self->state_ttype );

                        #$log->info("Asking Client ", $self->user, " for another TTYPE");
                        #$self->user->print(sprintf("%c%c%c%c%c%c",
                        #    TELOPT_IAC, TELOPT_SB,
                        #    TELOPT_TTYPE, 1,
                        #    TELOPT_IAC, TELOPT_SE,
                        #));
                    } elsif ( $self->state_got_naws ) {
                        if ( @{ $self->state_naws } == 4 ) {
                            my $naws = $self->state_naws;
                            $self->naws_w( ( $naws->[0] ? ( 255 + $naws->[0] ) : 0 ) + $naws->[1] );
                            $self->naws_h( ( $naws->[2] ? ( 255 + $naws->[2] ) : 0 ) + $naws->[3] );
                            $log->debug( 'Got NAWS: ', $self->naws_w, 'x', $self->naws_h ) if DEBUGTELNETOPTS;
                        } else {
                            #$log->debug( "Got NAWS but not 4 characters: ",
                            #    Dump( $self->state_naws ) );
                        }
                    }
                } else {
                    $log->debug(' => IAC SB UNKNOWN IAC !SE');
                    $log->warn( "Client ", $self->user,
                        ": shouldn't have received this (IAC=1, <240)" );
                    die "Garbage character received; Closing connection\r\n";
                }
                $self->state_got_ttype(0);
                $self->state_got_naws(0);
                $self->state_sb(-1);
                $self->state_will(-1);
                $self->state_do(-1);
                $self->state_iac(0);
                next;
            }
            next;
        }
        $log->fatal('die(help!)');
        die('help!');
    }
    $newdata =~ s/\x00//g;
    return $newdata;
}

1;
