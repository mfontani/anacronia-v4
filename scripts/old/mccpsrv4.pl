#!/usr/bin/perl -w
{

    package POE::Filter::Av4;    # for now, it's a stream filter (doesn't filter)
    use strict;
    use warnings;
    use POE::Filter;
    use lib './lib';
    use Av4::Telnet qw/%TELOPTS %TELOPTIONS/;
    use vars qw($VERSION @ISA);
    $VERSION = '0.01';
    @ISA     = qw(POE::Filter);

    sub new {
        my $type   = shift;
        my $buffer = '';
        my $self   = bless \$buffer, $type;
        $self;
    }

    sub clone {
        my $self   = shift;
        my $buffer = '';
        my $clone  = bless \$buffer, ref $self;
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

        #my $datalog = Log::Log4perl->get_logger('Av4.datalog');
        my @data = split( '', $datastr );
        foreach my $data (@data) {

           #$datalog->debug( "$direction $client: [", join( ',', unpack( 'C*', $data ), 10 ), "]" );
           #warn( "$direction $client: [", join( ',', unpack( 'C*', $data ), 10 ), "]", "\n");
            __byte_log( "Incoming", ord $data );
        }
    }

    # get() is inherited from POE::Filter.
    # 2001-07-27 RCC: The get_one() variant of get() allows Wheel::Xyz to
    # retrieve one filtered block at a time.  This is necessary for filter
    # changing and proper input flow control.  Although it's kind of
    # pointless for Stream, but it has to follow the proper interface.
    sub get_one_start {
        my ( $self, $stream ) = @_;
        foreach (@$stream) {
            warn __PACKAGE__ . "::get_one_start: got input\n";
            __data_log( 'Received from', $self, $_ );
        }
        $$self .= join '', @$stream;
    }

    sub get_one {
        my $self = shift;
        return [] unless length $$self;
        my $chunk = $$self;
        $$self = '';
        return [$chunk];
    }

    sub put {
        my ( $self, $chunks ) = @_;
        [@$chunks];
    }

    sub get_pending {
        my $self = shift;
        return [$$self] if length $$self;
        return undef;
    }
    1;
}

package main;
use strict;
use lib '../lib';
use IO::Socket;
use POE::Kernel { loop => 'POE::XS::Loop::Poll' };
use POE qw(
  Wheel::SocketFactory Wheel::ReadWrite Driver::SysRW Filter::Line
);

my %clients = ();

#==============================================================================
# This is the login state group.

#------------------------------------------------------------------------------
# Enter the "login" prompt state.  Prompt user, and wait for input.

sub login_login_start {
    my ( $session, $heap ) = @_[ SESSION, HEAP ];

    print "Session ", $session->ID, " - entering login state\n";

    # switch the output filter to stream
    $heap->{wheel}->set_output_filter( POE::Filter::Av4->new );

    # switch the input event to login_input
    $heap->{wheel}->event( InputEvent => 'login_input' );

    # display the prompt
    $heap->{wheel}->put('login: ');
}

sub login_login_input {
    my ( $kernel, $session, $heap, $input ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];

    print "Session ", $session->ID, " - received login input\n";

    if ( $input ne '' ) {
        $kernel->yield('password_start');
    } else {
        $kernel->yield('login_start');
    }
}

#==============================================================================
# This is the password state group.

sub login_password_start {
    my ( $session, $heap ) = @_[ SESSION, HEAP ];

    print "Session ", $session->ID, " - entering password state\n";

    # switch output filter to stream
    $heap->{wheel}->set_output_filter( POE::Filter::Av4->new );

    # switch input event to password_input
    $heap->{wheel}->event( InputEvent => 'password_input' );

    # display the prompt
    $heap->{wheel}->put('Password: ');
}

sub login_password_input {
    my ( $kernel, $session, $heap, $input ) = @_[ KERNEL, SESSION, HEAP, ARG0 ];

    print "Session ", $session->ID, " - received password input\n";

    # switch output filter to line
    $heap->{wheel}->set_output_filter( POE::Filter::Line->new );

    # display the response
    $heap->{wheel}->put('Login incorrect');

    # move to the login state
    $kernel->yield('login_start');
}

sub login_error {
    my ( $session, $heap, $operation, $errnum, $errstr ) = @_[ SESSION, HEAP, ARG0, ARG1, ARG2 ];

    $errstr = 'Client closed connection' unless $errnum;

    print( "Session ", $session->ID, ": login: $operation error $errnum: $errstr\n" );
    delete $clients{ $session->ID };

    delete $heap->{wheel};
}

#==============================================================================
# This is the main entry point for the login session.

sub login_session_start {
    my ( $kernel, $session, $heap, $handle, $peer_addr, $peer_port ) =
      @_[ KERNEL, SESSION, HEAP, ARG0, ARG1, ARG2 ];

    print "Session ", $session->ID, " - received connection\n";
    $clients{ $session->ID } = 1;
    warn "Total sessions: ", scalar keys %clients, "\n";

    # start reading and writing
    $heap->{wheel} = POE::Wheel::ReadWrite->new(
        'Handle' => $handle,
        'Driver' => POE::Driver::SysRW->new,

        #'Filter'     => POE::Filter::Line->new,
        'Filter'     => POE::Filter::Av4->new,
        'ErrorEvent' => 'error',
    );
    $heap->{wheel}->put( sprintf( "%c%c%c", 255, 251, 86 ) );    # IAC WILL COMPRESS2
    $heap->{wheel}->put( sprintf( "%c%c%c", 255, 253, 24 ) );    # IAC DO TTYPE
    $heap->{wheel}->put( sprintf( "%c%c%c", 255, 253, 31 ) );    # IAC DO NAWS
                                                                 # hello, world!\n
    $heap->{wheel}->put( 'FreeBSD (localhost) (ttyp2)', "\r\n\r\n" );
    $kernel->yield('login_start');
}

sub login_session_create {
    my ( $handle, $peer_addr, $peer_port ) = @_[ ARG0, ARG1, ARG2 ];

    POE::Session->create(
        inline_states => {
            _start => \&login_session_start,

            # general error handler
            error => \&login_error,

            # login prompt states
            login_start => \&login_login_start,
            login_input => \&login_login_input,

            # password prompt states
            password_start => \&login_password_start,
            password_input => \&login_password_input,
        },

        # start parameters
        args => [ $handle, $peer_addr, $peer_port ],
    );
    undef;
}

#==============================================================================

package main;

my $port = shift;
if ( not defined $port ) {
    print(
        "*** This program listens on port 23 by default.  You can change\n",
        "*** the port by putting a new one on the command line.  For\n",
        "*** example, to listen on port 10023:\n",
        "*** $0 10023\n",
    );
    $port = 23;
}

POE::Session->create(
    inline_states => {
        '_start' => sub {
            my $heap = $_[HEAP];

            $heap->{wheel} = POE::Wheel::SocketFactory->new(
                BindPort     => $port,
                SuccessEvent => 'socket_ok',
                FailureEvent => 'socket_error',
                Reuse        => 'yes',
            );
        },

        'socket_error' => sub {
            my ( $session, $heap, $operation, $errnum, $errstr ) =
              @_[ SESSION, HEAP, ARG0, ARG1, ARG2 ];
            print( "Session ", $session->ID, ": listener: $operation error $errnum: $errstr\n" );
        },

        'socket_ok' => \&login_session_create,
    },
);

$poe_kernel->run();

__END__

