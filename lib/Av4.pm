package Av4;
use strict;
use warnings;
use POSIX;
use IO::Socket;
use POE::Kernel { loop => 'POE::XS::Loop::EPoll' };

# POE::XS::Queue::Array is used by default by POE if found
use POE;
use Log::Log4perl;
use YAML;

use Av4::Utils qw/get_logger ansify/;

require Av4::Server;

use Av4::HelpParse;
use Av4::Telnet qw/
  %TELOPTS %TELOPTIONS
  TELOPT_FIRST
  TELOPT_WILL TELOPT_WONT
  TELOPT_DO TELOPT_DONT
  TELOPT_IAC TELOPT_SB TELOPT_SE
  TELOPT_COMPRESS2
  TELOPT_TTYPE TELOPT_NAWS TELOPT_MSP TELOPT_MXP
  _256col
  /;

# general settings
our $listen_port = 8081;

# general stats
our $mud_chars_sent         = 0;    # characters sent by mud
our $mud_chars_sent_nonmccp = 0;    # how many of these weren't compressed
our $mud_chars_sent_mccp    = 0;    # how many of these were compressed
our $mud_data_sent          = 0;    # data effectively sent
our $mud_data_sent_nonmccp  = 0;    # data sent uncompressed
our $mud_data_sent_mccp     = 0;    # data sent compressed

# time and other stats
our $mud_start              = 0;
our $cmd_processed          = 0;

# defaults for ticks
our $tick_commands = 1.0;

our $shutdown_connected = 0;

sub new {
    my $class = shift;
    my $opts  = {@_};
    $opts->{fake} = 0 if ( !defined $opts->{fake} );
    $opts->{helpfile} = 'help.are' if ( !defined $opts->{helpfile} );
    if ( !$opts->{fake} ) {
        Log::Log4perl::init_and_watch( 'log.conf', 'HUP' );
    } else {
        my $conf = q{
            log4perl.category.Av4 = DEBUG, Screen
            log4perl.category.main.new_dispatch_command = TRACE, Screen
            log4perl.category.Av4.HelpParse = WARN, Screen
            log4perl.appender.Screen = Log::Log4perl::Appender::Screen
            log4perl.appender.Screen.stderr = 0
            log4perl.appender.Screen.layout = PatternLayout
            log4perl.appender.Screen.layout.ConversionPattern=%d %F:%L %M %p %m%n
        };
        Log::Log4perl::init( \$conf );
    }
    my $self = {};
    POE::Session->create(
        inline_states => {
            _start        => \&server_start,
            event_accept  => \&server_accept,
            event_read    => \&client_read,
            event_write   => \&client_write,
            event_error   => \&client_error,
            event_quit    => \&client_quit,
            event_done    => \&client_done,
            tick_commands => \&tick_commands,
            shutdown      => \&server_shutdown,
        },
        heap => $self,
    ) if ( !$opts->{fake} );
    my $server = Av4::Server->new(
        helps  => Av4::HelpParse::areaparse($opts->{helpfile}),
        kernel => $poe_kernel,
    );
    $listen_port   = $opts->{listen_port}   if ( defined $opts->{listen_port} );
    $tick_commands = $opts->{tick_commands} if ( defined $opts->{tick_commands} );
    $self->{server} = $server;
    return bless $self, $class;
}

sub server {
    my $self = shift;
    $self->{server};
}

sub run {
    my $self    = shift;
    my $log     = get_logger();
    my $CLRTEST = "&xx&rr&gg&yy&pp&bb&cc&ww &XX&RR&GG&YY&PP&BB&CC&WW";
    $log->warn("TCP ready on port $listen_port");

    #$log->debug($CLRTEST);
    #$log->debug( ansify($CLRTEST) );
    $mud_start = time();
    $poe_kernel->run();
    exit 0;
}
{
    my $shutdown_by = '';

    sub shutdown {
        my ( $self, $bywho ) = @_;
        $shutdown_by = $bywho->id;
        $bywho->server->running(0);
    }
    sub shutdown_by { $shutdown_by }

    sub server_shutdown {
        my @children = $poe_kernel->_data_ses_get_children($poe_kernel);
        foreach my $child (@children) {
            warn "Killing child $child\n";
            $poe_kernel->_data_ses_stop($child);
        }
        my $mud_uptime = time() - $mud_start;
        warn sprintf( "Clients connected: $shutdown_connected\n" );
        warn sprintf( "MUD chars sent:       %20lu (%20.2f b/s)\n",   $mud_chars_sent,         $mud_chars_sent / $mud_uptime );
        warn sprintf( "MUD chars sent !mccp: %20lu (%20.2f b/s)\n",   $mud_chars_sent_nonmccp, $mud_chars_sent_nonmccp / $mud_uptime );
        warn sprintf( "MUD chars sent mccp:  %20lu (%20.2f b/s)\n",   $mud_chars_sent_mccp,    $mud_chars_sent_mccp / $mud_uptime );
        warn sprintf( "MUD data sent:        %20lu (%20.2f KiB/s)\n", $mud_data_sent,          $mud_data_sent / 1024 / $mud_uptime );
        warn sprintf( "MUD data sent !mccp:  %20lu (%20.2f KiB/s)\n", $mud_data_sent_nonmccp,  $mud_data_sent_nonmccp / 1024 / $mud_uptime );
        warn sprintf( "MUD data sent mccp:   %20lu (%20.2f KiB/s)\n", $mud_data_sent_mccp,     $mud_data_sent_mccp /1024 / $mud_uptime );
        warn sprintf( "Processed %d commands in %d seconds: %2.2f commands/second\n",$cmd_processed,$mud_uptime,($cmd_processed/$mud_uptime));
        warn sprintf( "Cache hits:           %d\n", $Av4::Utils::hits);
        warn sprintf( "Cache misses:         %d\n", $Av4::Utils::misses);
        warn "Stopped now\n";
    }
}

sub server_start {
    my $self     = $_[HEAP];
    my $listener = IO::Socket::INET->new(
        LocalPort => $listen_port,
        Listen    => 50,
        Reuse     => "yes",
        Blocking  => 0,
    ) or die "can't make server socket: $@\n";
    $_[KERNEL]->select_read( $listener, "event_accept" );
    $_[KERNEL]->delay( tick_commands => 0 );
}

sub check_shutdown {
    my ( $self, $kernel ) = @_;
    return 0 if $self->server->running;
    $shutdown_connected = scalar @{ $self->server->clients };
    foreach my $client ( @{ $self->server->clients } ) {
        next if ( !defined $client );
        $client->print( "\n\nShutting down -- Initiated by ", shutdown_by(), "\n\n" );
        $kernel->select_write( $client->id, 'event_write' );
    }
    $kernel->delay( shutdown => 1 );
    return 1;
}

sub tick_commands {
    my ( $self, $kernel, $server ) = @_[ HEAP, KERNEL, ARG0 ];
    my @clients = grep { defined $_ } @{ $self->server->clients };
    $self->server->clients( \@clients );
    return if check_shutdown( $self, $kernel );
    foreach my $client ( @{ $self->server->clients } ) {
        next if ( !defined $client );
        $client->delay(
              $client->delay - 1 >= 0
            ? $client->delay - 1
            : 0
        );
        my ( $dispatched, $redispatch ) = $client->dispatch_command( $_[KERNEL] );
        if ( defined $dispatched ) {
            push @{ $client->commands_dispatched }, $dispatched;
        }
        if ( exists $self->server->outbuffer->{ $client->id } ) {
            $kernel->select_write( $client->id, "event_write" );
        }
        redo if ( defined $redispatch && $redispatch );

        #$client->print( $client->prompt )
        #  if ( defined $dispatched && (
        #        $dispatched !~ /^\s*quit\s*$/
        #        && $dispatched !~ /^\s*\@$/
        #    )
        #);
    }
    $_[KERNEL]->delay( tick_commands => $tick_commands );
}

sub server_accept {
    my ( $self, $kernel, $server ) = @_[ HEAP, KERNEL, ARG0 ];
    my $new_client = $server->accept();
    my $new_user   = Av4::User->new(
        id    => $new_client,
        queue => [],
        server => $self->server,
    );
    push @{ $self->server->clients }, $new_user;
    $new_user->print( sprintf( "%c%c%c", TELOPT_IAC, TELOPT_WILL, TELOPT_COMPRESS2 ) );
    $new_user->print( sprintf( "%c%c%c", TELOPT_IAC, TELOPT_DO,   TELOPT_TTYPE ) );
    $new_user->print( sprintf( "%c%c%c", TELOPT_IAC, TELOPT_DO,   TELOPT_NAWS ) );
    $new_user->print( sprintf( "%c%c%c", TELOPT_IAC, TELOPT_WILL, TELOPT_MSP ) );
    $new_user->print( sprintf( "%c%c%c", TELOPT_IAC, TELOPT_WILL, TELOPT_MXP ) );
    $new_user->print( '#$#mcp version: 2.1 to: 2.1', "\r\n" );
    $new_user->print("Hi, Welcome to the MUD!\r\n\r\n"); # FIXME BANNER
    $new_user->print( $new_user->prompt );

    $new_user->print(sprintf "\33]0;Av4 - $new_user\a");
    $kernel->select_read( $new_client, "event_read" );
}

sub __data_log {
    my ( $direction, $client, $datastr ) = @_;
    my $datalog = Log::Log4perl->get_logger('Av4.datalog');
    my @data = split( '', $datastr );
    foreach my $data (@data) {
        $datalog->debug( "$direction $client: [", join( ',', unpack( 'C*', $data ) ), "]" );
    }
}

sub client_read {
    my ( $self, $kernel, $client ) = @_[ HEAP, KERNEL, ARG0 ];
    my $log = get_logger();
    my ($user) =
      grep { defined $_ && $_->id == $client } @{ $self->server->clients };
    die "Cant find user $client in clients!" if ( !defined $user );
    my $data = "";
    my $rv = $client->recv( $data, POSIX::BUFSIZ, 0 );
    unless ( defined($rv) and length($data) ) {
        $kernel->yield( event_error => $client );
        return;
    }

    #__data_log( 'Received from', $client, $data );    # ONLY FOR DEBUG!
    #eval { $data = $self->_analyze_data( $data, $client ); };
    eval { $data = $user->received_data($data); };
    if ($@) {
        $log->error("Quitting client $client: $@");
        $kernel->yield( event_write => $client );    # flushes all output
        $kernel->yield( event_error => $client );    # quits
             #$user->commands->cmd_get('quit')->( $kernel, $client, $user, undef );
        return;
    }
    $self->server->inbuffer->{$client} .= $data;
    while ( $self->server->inbuffer->{$client} =~ s/(.*\n)// ) {
        my $typed = $1;
        chomp($typed);
        $typed =~ s/[\x0D\x0A]//gm;
        if ( @{ $user->queue } > 80 && $typed !~ /^\s*quit/ ) {
            $typed = 'quit';
            $user->broadcast(
                $kernel, $client,
                "&W$user &Gquits due to spamming\n\r",
                "&WYou &Gquit due to SPAMMING!\n\r",
                1,    # send prompt to others
            );
            $log->info("Client $client SPAMMING (queue>80) ==> OUT!");
        }
        push @{ $user->queue }, $typed;
        #$cmd_processed++;
        #$typed =~ s/[\x00-\x19\x80-\xFF]//gi;
        #$log->info( "Added to command stack for $client: `$typed`:\n\r" . Dump( $user->queue ) );
    }

    # commands are now dispatched via tick_commands
}

sub client_write {
    my ( $self, $kernel, $client ) = @_[ HEAP, KERNEL, ARG0 ];

    #my $log = get_logger();
    #$log->info("Entered client_write for client $client");
    unless ( exists $self->server->outbuffer->{$client} ) {
        #$kernel->select_write($client);
        #$log->info("No data to be sent for client $client");
        return;
    }

    my ($user) =
      grep { defined $_ && $_->id == $client } @{ $self->server->clients };
    die "Cant find user $client in clients!" if ( !defined $user );

    #__data_log( 'Sent to', $client, $self->server->outbuffer->{$client} );

    my $data       = $self->server->outbuffer->{$client};
    my $datalength = length $data;

    my $rv;
    eval {
        $rv = $client->send( $data, 0 );
        if ($@) {
            get_logger()->warn("Error Client->send: $@");
            $kernel->yield( event_error => $client );
            return;
        }
    };
    unless ( defined $rv ) {
        get_logger->warn("Client $client: Cant send data\n");
        return;
    }
    if (   $rv == $datalength
        or $! == POSIX::EWOULDBLOCK )
    {
        delete $self->server->outbuffer->{$client};
        return;
    }
    get_logger->warn("Client $client: error ->send\n");
    $kernel->yield( event_error => $client );
}

sub broadcast {
    my ( $self, $kernel, $message, $sendprompt ) = @_;
    $sendprompt = 0 if ( !defined $sendprompt );
    my $log = get_logger();
    $log->info("Server broadcast: $message");

    # Send it to everyone.
    foreach my $user ( @{ $self->server->clients } ) {
        next if ( !defined $user );
        #$log->info("Sending broadcast to client $user");
        $user->print( ansify( $message ));
        $user->print( $user->prompt ) if ($sendprompt);
        $kernel->yield( event_write => $user->id );
    }
}

sub client_quit {
    my ( $self, $kernel, $client ) = @_[ HEAP, KERNEL, ARG0 ];
    #my $log = get_logger();
    $self->broadcast(
        $kernel,
        "&W$client &Gquits the MUD\n\r",
        1,    # send prompt to others
    );
    $kernel->yield( event_write => $client );    # flushes all output
    $kernel->yield( event_done  => $client );
}

sub client_error {
    my ( $self, $kernel, $client ) = @_[ HEAP, KERNEL, ARG0 ];
    my $log = get_logger();
    $self->broadcast(
        $kernel,
        "&W$client &Gquits the MUD due to errors\n\r",
        1,                                       # send prompt to others
    );
    $kernel->yield( event_done => $client );
}

sub client_done {
    my ( $self, $kernel, $client ) = @_[ HEAP, KERNEL, ARG0 ];
    my $log = get_logger();
    delete $self->server->inbuffer->{$client};
    delete $self->server->outbuffer->{$client};

    # remove from @clients
    for ( 0 .. $#{ $self->server->clients } ) {
        next if ( !defined $self->server->clients->[$_] );
        if ( $self->server->clients->[$_]->id == $client ) {
            delete $self->server->clients->[$_];
            last;
        }
    }
    my @clients = grep { defined $_ } @{ $self->server->clients };
    $self->server->clients( \@clients );
    $kernel->select($client);
    close $client;
    $log->info("Session ended for client $client");
}

1;
