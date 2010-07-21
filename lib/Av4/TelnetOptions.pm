package Av4::TelnetOptions;
use Av4::User;
use Moose;
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
  _256col
  /;

## the user these telnet options negotiations refer to
has 'user' => ( is => 'ro', isa => 'Av4::User', required => 1 );

## negotiated options' values
has 'mccp'         => ( is => 'rw', isa => 'Int', required => 1, default => 0 );
has 'terminaltype' => ( is => 'rw', isa => 'Str', required => 1, default => 'undefined' );
has 'naws_w'       => ( is => 'rw', isa => 'Int', required => 1, default => 0 );
has 'naws_h'       => ( is => 'rw', isa => 'Int', required => 1, default => 0 );

## State of the telnet state machine
has 'state_iac'  => ( is => 'rw', isa => 'Int', required => 1, default => 0 );
has 'state_do'   => ( is => 'rw', isa => 'Int', required => 1, default => -1 );
has 'state_sb'   => ( is => 'rw', isa => 'Int', required => 1, default => -1 );
has 'state_will' => ( is => 'rw', isa => 'Int', required => 1, default => -1 );

## State of the options negotiations
has 'state_got_ttype' => ( is => 'rw', isa => 'Int', required => 1, default => 0 );
has 'state_ttype'     => ( is => 'rw', isa => 'Str', required => 1, default => '' );
has 'state_got_naws'  => ( is => 'rw', isa => 'Int', required => 1, default => 0 );
has 'state_naws' => ( is => 'rw', isa => 'ArrayRef[Int]', required => 1, default => sub { [] } );

## MCCP zlib stream
has 'zstream' => ( is => 'rw', isa => 'Any', required => 1, default => 0 );

sub send_data {
    my $self   = shift;
    my $out    = shift;
    my $lenout = length $$out;
    #my $log  = get_logger();
    if ( !$self->mccp ) {
        #$log->trace( "Sending data to client ", $self->user, " via plain text" );
        $Av4::mud_chars_sent         += $lenout;
        $Av4::mud_chars_sent_nonmccp += $lenout;
        $Av4::mud_data_sent          += $lenout;
        $Av4::mud_data_sent_nonmccp  += $lenout;
        $self->user->server->outbuffer->{ $self->user->id } .= $$out;
        return;
    }
    if ( !$self->zstream ) {
        #$log->error( "Client ", $self->user, " has MCCP enabled but no zstream!" );
        $self->user->server->kernel->yield( event_error => $self->user->id );
        return;
    }
    my ( $outdeflate, $deflatestatus ) = $self->zstream->deflate($$out);
    if ( !defined $outdeflate ) {
        #$log->error( "Client ", $self->user, ": undefined deflate: status ", $deflatestatus );
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
    $self->user->server->outbuffer->{ $self->user->id } .= $outdeflate;
    my ( $outflush, $flushstatus ) = $self->zstream->flush(Z_SYNC_FLUSH);
    if ( !defined $outflush ) {
        #$log->error( "Client ", $self->user, ": undefined flush: status ", $flushstatus );
        $self->user->server->kernel->yield( event_error => $self->user->id );
        return;
    }
    #$log->trace(
    #    "Client ", $self->user,
    #    " via mccp, flushed is ",
    #    length $outflush,
    #    "; added to buffer!"
    #);
    $Av4::mud_data_sent      += length $outflush;
    $Av4::mud_data_sent_mccp += length $outflush;
    $self->user->server->outbuffer->{ $self->user->id } .= $outflush;
    $self->user->server->kernel->select_write( $self->user->id, 'event_write' );
}

sub mccp2start {
    my $self = shift;
    my $log  = get_logger();
    $log->info( "Sending IAC SB COMPRESS2 IAC SE to client ", $self->user );
    $self->user->server->outbuffer->{ $self->user->id } .= sprintf(
        "%c%c%c%c%c", 255, 250, 86, 255, 240    # IAC SB COMPRESS2 IAC SE
    );
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
    #$log->debug( "_analyze_data: str length ", length $data );
    my $charno = 0;

    foreach my $char ( split( '', $data ) ) {
        #$log->debug(
        #    "$charno) Got character: ",
        #    "dec ", sprintf( "%d", ord $char ),
        #    " hex ", sprintf( "%x", ord $char ), ' '
        #);
        $charno++;
        if ( $self->state_iac == 0 ) {    # only IAC or standard characters allowed
            #$log->trace('$iac == 0');
            if ( ord $char == TELOPT_IAC ) {
                $self->state_iac(1);
                #$log->debug("IAC\n");
                next;
            } elsif ( ord $char >= TELOPT_FIRST ) {
                $log->warn( "Client ", $self->user, ": shouldn't have received this (!IAC, >240)" );
                die "&RGarbage character received; Closing connection\r\n";
            }
            $newdata .= $char;
            next;
        } elsif ( $self->state_iac == 1 ) {    # Got IAC, waiting on DO/DONT, etc
            #$log->trace('$iac == 1');
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
                #$log->debug( $TELOPTS{ ord $char }, "\n" );
                next;
            }
            $newdata .= $char;
            next;
        } elsif ( $self->state_iac == 2 ) {    # Got IAC DO/DONT/WILL/WONT/SB, waiting on option
            #$log->trace('$iac == 2');
            if ( defined $TELOPTIONS{ ord $char } ) {
                #$log->debug( $TELOPTIONS{ ord $char }, '!' );
                if ( $self->state_do == 1 ) {
                    #$log->debug(" => IAC DO!!");
                    if ( ord $char == TELOPT_COMPRESS2 ) {
                        $self->mccp2start();
                        #$log->info( "Client ", $self->user, " OK COMPRESS2 STARTS" );
                    }
                } elsif ( $self->state_do == 0 ) {
                    #$log->debug( " => IAC DONT ", $TELOPTIONS{ ord $char } );
                    if ( ord $char == TELOPT_COMPRESS2 ) {
                        $self->mccp2end();
                        #$log->info( "Client ", $self->user, "OK COMPRESS2 STOP" );
                    }
                } elsif ( $self->state_will == 1 ) {
                    #$log->debug(" => IAC WILL!!");
                    if ( ord $char == TELOPT_TTYPE ) {
                        #$log->info( "Client ", $self->user, " CAN DO TTYPE" );
                        $self->user->print(
                            sprintf( "%c%c%c%c%c%c",
                                TELOPT_IAC, TELOPT_SB, TELOPT_TTYPE, 1, TELOPT_IAC, TELOPT_SE, )
                        );

                        # TODO multiple terminal types
                    } elsif ( ord $char == TELOPT_NAWS ) {
                        #$log->debug( "Client ", $self->user, " CAN DO NAWS" );
                    }
                } elsif ( $self->state_will == 0 ) {
                    #$log->debug( " => IAC WONT ", $TELOPTIONS{ ord $char } );
                } elsif ( $self->state_sb == 1 ) {
                    #$log->debug(" => IAC SB!!");
                    if ( ord $char == TELOPT_TTYPE ) {
                        #$log->debug( "Client ", $self->user, " SB TTYPE" );
                        $self->state_got_ttype(1);
                        $self->state_ttype('');
                        $self->state_sb(2);
                    } elsif ( ord $char == TELOPT_NAWS ) {
                        #$log->debug( "Client ", $self->user, " SB NAWS" );
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
            #$log->trace('$iac == 3');
            if ( $self->state_sb == 2 ) {      # Got IAC SB OPTION, waiting on DATA
                if ( $self->state_got_ttype ) {
                    if ( ord $char == 0 ) {
                        #$log->debug(' => IAC SB TTYPE 0!');
                        $self->state_sb(3);
                    } else {
                        #$log->debug(' => IAC SB TTYPE ??');
                        $self->state_sb(3);
                    }
                } elsif ( $self->state_got_naws ) {
                    #$log->debug( "Got char for NAWS: ", sprintf( "%d", ord $char ) );
                    push @{ $self->state_naws }, ord $char;
                    if ( @{ $self->state_naws } == 4 ) {
                        #$log->debug("NAWS received 4 scalars, awaiting IAC");
                        $self->state_sb(3);
                    }
                } else {
                    #$log->debug(' => IAC SB UNKNOWN awaiting IAC');
                }
            } elsif ( $self->state_sb == 3 ) {    # got IAC SB OPTION DATA, waiting on IAC
                if ( $self->state_got_ttype ) {
                    if ( ord $char == TELOPT_IAC ) {
                        #$log->debug(' => IAC SB TTYPE DATA [..] IAC!');
                        $self->state_sb(4);
                    } else {
                        #$log->debug( ' => IAC SB TTYPE DATA newchar: ', $char );
                        $self->state_ttype( $self->state_ttype . $char );
                    }
                } elsif ( $self->state_got_naws ) {
                    if ( ord $char == TELOPT_IAC ) {
                        #$log->debug(' => IAC SB NAWS [..] IAC!');
                        $self->state_sb(4);
                    } else {
                        #$log->debug( ' => IAC SB NAWS unknown char: ', $char );
                        #$ttype .= $char;
                    }
                } else {
                    #$log->debug(' => IAC SB UNKNOWN awaiting IAC');
                }
            } elsif ( $self->state_sb == 4 ) {    # Got IAC SB OPTION DATA IAC, waiting on SE
                if ( ord $char == TELOPT_SE ) {
                    #$log->debug(' => IAC SB OPTION DATA IAC SE!');
                    if ( $self->state_got_ttype ) {
                        #$log->debug( 'GOT TTYPE: >', $self->state_ttype, '<' );
                        #$self->user->print( 'Your terminal type is:', $self->state_ttype, "\r\n" );
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
                            #$log->debug( 'Got NAWS: ', $self->naws_w, 'x', $self->naws_h );
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

__PACKAGE__->meta->make_immutable();
no Moose;
1;
