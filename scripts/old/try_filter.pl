#!/usr/bin/perl -w
{

    package POE::Filter::Av4;    # for now, it's a stream filter (doesn't filter)
    use strict;
    use warnings;
    use POE::Filter;

    #use POE::Filter::Block;
    use Carp;
    use lib './lib';
    use Av4::Telnet qw/
      %TELOPTS %TELOPTIONS
      TELOPT_FIRST
      TELOPT_WILL TELOPT_WONT
      TELOPT_DO TELOPT_DONT
      TELOPT_IAC TELOPT_SB TELOPT_SE
      TELOPT_COMPRESS2
      TELOPT_TTYPE TELOPT_NAWS
      /;
    use YAML;
    use vars qw($VERSION @ISA);
    $VERSION = '0.01';
    @ISA     = qw(POE::Filter);

    sub new {
        my $type   = shift;
        my $buffer = '';
        my $self   = {};      #POE::Filter::Block->new( Blocksize => 1 );
        $self->{INPUTBUFFER} = '';

        # couples of DO|DONT|WILL|WONT => {OPTION=>CODEREF}
        # DEFAULT => CODEREF
        $self->{CODEREFS} = {@_};
        confess "Need DEFAULT=>CODEREF" if ( !defined $self->{CODEREFS}->{DEFAULT} );
        $self->{DATABUFFER} = '';
        warn "Created new ", __PACKAGE__, " with coderefs: ", Dump( $self->{CODEREFS} ), "\n";
        bless $self, $type;
        return $self;
    }

    sub clone {
        my $self  = shift;
        my $clone = {
            INPUTBUFFER => '',
            CODEREFS    => {@_},
            DATABUFFER  => '',
        };
        bless \$clone, ref $self;
        return $clone;
    }

    sub __byte_log {
        my ( $direction, $byte ) = @_;
        printf( "%-10s %3d ", $direction, $byte );
        printf( "%-10s ", defined $TELOPTS{$byte}    ? $TELOPTS{$byte}    : '?' );
        printf( "%-10s ", defined $TELOPTIONS{$byte} ? $TELOPTIONS{$byte} : '?' );
        if    ( $byte == 10 ) { printf("10") }
        elsif ( $byte == 13 ) { printf("13") }
        elsif ( $byte == 27 ) { printf("ESC/OUTMARK (27)") }
        elsif ( $byte >= 32 && $byte < 126 ) { printf( "[%c]",  $byte ) }
        else                                 { printf( "?? %d", $byte ) }
        printf "\n";
        return;
    }

    sub __data_log {
        my ( $direction, $client, $datastr ) = @_;
        my @data = split( '', $datastr );
        print "__data_log: Got data: ", scalar length $datastr, " bytes\n";
        foreach my $data (@data) {
            __byte_log( "Incoming", ord $data );
        }
        return $datastr;
    }

    ##### TELNET STATE MACHINE

    # helper:
    sub s_telopt {
        my ( $self, $which ) = @_;
        return $TELOPTS{$which} if defined $TELOPTS{$which};
        return '??';
    }

    sub s_teloption {
        my ( $self, $which ) = @_;
        return $TELOPTIONS{$which} if defined $TELOPTIONS{$which};
        return '??';
    }

    ## TODO: return -1 or something in case there isn't enough data to be parsed via telnet?

    sub __telnet_statemachine {
        my ( $self, $direction, $client, $datastr ) = @_;
        __data_log( $direction, $client, $datastr );
        my @bytes = split( '', $datastr );
        for ( my $ichar = 0 ; $ichar <= $#bytes ; ) {
            if ( ord $bytes[$ichar] == TELOPT_IAC ) {
                if ( defined $bytes[ $ichar + 1 ]
                    && ord $bytes[ $ichar + 1 ] == TELOPT_IAC )
                {    # IAC IAC => literal 255
                    $self->{DATABUFFER} .= $bytes[$ichar];    # 255
                    $ichar += 2;
                    next;
                }
                $ichar++;
                $ichar += $self->__got_iac( \@bytes, $ichar );    # handle IAC stuff
                next;
            }
            $self->{DATABUFFER} .= $bytes[$ichar];
            $ichar++;
        }
    }

    sub __got_iac {
        my ( $self, $bytes, $origindex ) = @_;

        # IAC DO|DONT|WILL|WONT OPTION
        # IAC SB XXXXX IAC SE
        my $telopt = ord $bytes->[$origindex];
        if (   $telopt != TELOPT_DO
            && $telopt != TELOPT_DONT
            && $telopt != TELOPT_WILL
            && $telopt != TELOPT_WONT
            && $telopt != TELOPT_SB )
        {

            # no clue => treat as data, bye
            warn "__got_iac => got unknown telopt $telopt, pushing back";
            $self->{DATABUFFER} .= $bytes->[$origindex];
            return 0;
        }

        # ok it's DO|DONT|WILL|WONT|SB
        warn "__got_iac => DO|DONT|WILL|WONT|SB, going ahead..";

        # bail if no other bytes (at least two for IAC XX OPTION)
        if ( !defined $bytes->[ $origindex + 1 ] && !defined $bytes->[ $origindex + 2 ] ) {
            warn "__got_iac => no more bytes, returning -1";
            return -1;
        }

        # easy ones : DO|DONT|WILL|WONT
        if (   $telopt == TELOPT_DO
            || $telopt == TELOPT_DONT
            || $telopt == TELOPT_WILL
            || $telopt == TELOPT_WONT )
        {
            my $option = ord $bytes->[ $origindex + 1 ];
            if (   !defined $TELOPTIONS{$option}
                || !defined $self->{CODEREFS}->{ $TELOPTS{$telopt} }
                || !defined $self->{CODEREFS}->{ $TELOPTS{$telopt} }->{ $TELOPTIONS{$option} } )
            {
                $self->{CODEREFS}->{DEFAULT}->( $self, $telopt, $option );   # calls default handler
                return 2;    # NN + OPTION have been parsed and handled
            }
            $self->{CODEREFS}->{ $TELOPTS{$telopt} }->{ $TELOPTIONS{$option} }
              ->( $self, $telopt, $option );    # calls asked handler
            return 2;                           # NN + OPTION have been parsed & handled
        }

        $self->{DATABUFFER} .= $bytes->[$origindex];
        return 0;
    }

    ##### END TELNET STATE MACHINE

    sub get {
        confess("->get() should *never* be called for this filter!");
    }

    sub get_one_start {
        my ( $self, $stream ) = @_;
        $self->{INPUTBUFFER} .= join '', @$stream;
        $self->__telnet_statemachine( 'Parsing from ', $self, $self->{INPUTBUFFER} );
    }

    sub get_one {
        my $self = shift;
        return [] unless length $self->{DATABUFFER};
        my $chunk = $self->{DATABUFFER};
        $self->{DATABUFFER} = '';
        return [$chunk];
    }

    sub put {
        my ( $self, $chunks ) = @_;
        [@$chunks];
    }

    sub get_pending {
        my $self = shift;
        return [ $self->{DATABUFFER} ] if length $self->{DATABUFFER};
        return undef;
    }
    1;
}

package main;
use strict;
use warnings;
use IO::Socket;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Component::Client::TCP);
use YAML;
use File::Slurp qw/slurp/;
use 5.010_000;

my $datafile = shift;
die "$0: need datafile\n" if ( !defined $datafile );
my $data = data_received($datafile);
say "\e[2J";
say '#' x 72;
say "Data received:";
say '#' x 72;
print $data;
say '#' x 72;

POE::Session->create(
    inline_states => {
        _start => sub {
            $_[HEAP]{server} = POE::Wheel::SocketFactory->new(
                BindPort     => 12345,
                SuccessEvent => 'on_client_accept',
                FailureEvent => 'on_server_error',
                Reuse        => 'yes',
            );
        },
        on_client_accept => sub {
            my $sock     = $_[ARG0];
            my $io_wheel = POE::Wheel::ReadWrite->new(
                Handle      => $sock,
                InputEvent  => 'on_client_input',
                ErrorEvent  => 'on_client_error',
                InputFilter => POE::Filter::Av4->new(
                    'DO' => {
                        'COMPRESS2' => sub {
                            my ( $self, $telopt, $option ) = @_;
                            warn "Wheel->$sock will *do* COMPRESS2, enabling\n";
                        },
                    },
                    'DONT' => {
                        'COMPRESS2' => sub {
                            my ( $self, $telopt, $option ) = @_;
                            warn "Wheel->$sock *wont do* COMPRESS2, disabling\n";
                        },
                    },
                    'WILL' => {
                        'TTYPE' => sub {
                            my ( $self, $telopt, $option ) = @_;
                            warn "Wheel->$sock *will* do TTYPE, awaiting..\n";
                        },
                    },
                    'WONT' => {
                        'TTYPE' => sub {
                            my ( $self, $telopt, $option ) = @_;
                            warn "Wheel->$sock *wont do* TTYPE :(\n";
                        },
                    },
                    DEFAULT => sub {
                        my ( $self, $telopt, $option ) = @_;
                        my $s_telopt    = $self->s_telopt($telopt);
                        my $s_teloption = $self->s_teloption($option);
                        warn "Wheel->$sock UNKNOWN $telopt ($s_telopt) / $option ($s_teloption)\n";
                    },
                ),
            );
            $_[HEAP]{client}{ $io_wheel->ID() } = $io_wheel;
        },
        on_server_error => sub {
            my ( $operation, $errnum, $errstr ) = @_[ ARG0, ARG1, ARG2 ];
            warn "Server $operation error $errnum: $errstr\n";
            delete $_[HEAP]{server};
        },
        on_client_input => sub {
            my ( $input, $wheel_id ) = @_[ ARG0, ARG1 ];
            warn "Server got input from client: ", $input;

            #$input =~ tr[a-zA-Z][n-za-mN-ZA-M]; # ASCII rot13
            #$_[HEAP]{client}{$wheel_id}->put($input);
        },
        on_client_error => sub {
            my $wheel_id = $_[ARG3];
            delete $_[HEAP]{client}{$wheel_id};
        },
    },
);

POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->delay( 'create_client'     => 3 );
            $_[KERNEL]->delay( 'disconnect_client' => 6 );
        },
        create_client => sub {
            POE::Component::Client::TCP->new(
                RemoteAddress => '127.0.0.1',
                RemotePort    => 12345,

                #Alias => 'myclient',
                Connected => sub {
                    warn "Client connected to server, sending data";
                    $_[HEAP]{server}->put($data);
                },
                ServerInput => sub {
                    my $input = $_[ARG0];
                    warn "Client got data from server: ", $input;
                }
            );
        },
        disconnect_client => sub {
            warn "Disconnecting\n";
            exit;
        },
    },
);

POE::Kernel->run();
exit;

my $filter = POE::Filter::Av4->new();
say "Filtering (get_one_start):";
$filter->get_one_start( [ data_received($datafile) ] );
while (1) {
    say '#' x 72;
    say "Parsing (get_one):";
    my $data = $filter->get_one();
    last unless @$data;
    say "Got data: >>>", $data->[0], "<<<";
}
say '#' x 72;

sub data_received {
    my $filename = shift;
    my @data     = slurp($filename);
    my $lineno   = 0;
    my $data     = '';
    foreach my $dataline (@data) {
        $lineno++;
        my ( $direction, $handle, $arrdata ) =
          $dataline =~ /^(Sent|Received)\s.*\s(.*)\:\s*\[([\d\,]+)\]\s*$/;
        if ( !defined $direction || !defined $handle || !defined $arrdata ) {
            die "Line $lineno: regexp didn't catch!\n";
        }
        next if ( $direction !~ /Received/i );
        my @arr = split( ',', $arrdata );
        $data .= pack( 'C*', @arr );
    }
    return $data;
}

