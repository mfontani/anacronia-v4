package Av4;
use 5.010_001;    # at least
use strict;
use warnings;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Gearman::Client;
use Time::HiRes qw/tv_interval gettimeofday time/;

use Log::Log4perl;
use YAML;

use Av4::Help;
use Av4::Area;
use Av4::AreaParse;
use Av4::Entity;
use Av4::Entity::Player;
use Av4::Entity::Mobile;
require Av4::Utils;
require Av4::Server;
require Av4::Command;            # access to %time_taken_by_command
require Av4::Commands::Basic;    # to invalidate the who list

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

# When using Devel::NYTProf, it seems that AnyEvent's way of trying to use
# Time::HiRes's 'time' for its own 'time' and 'now' doesn't quite work, and it
# ends up creating a ton of evals whenever AnyEvent's time() or now() is called.
# This in turn creates slowness and slugginesh of the whole thing, _and_ makes
# running nytprofhtml the sort of thing you go on holidays whilst it does its
# thing. With the below block, I don't need to go make a coffee while nytprof
# runs.
{

    package AE;
    no warnings 'redefine';
    sub time () { goto &Time::HiRes::time }
    sub now ()  { goto &Time::HiRes::time }

    package AnyEvent;
    sub time () { goto &Time::HiRes::time }
    sub now ()  { goto &Time::HiRes::time }
}

# general settings -- these *may* be used somewhere else, hence they're 'our' vars
our $listen_address = undef;
our $listen_port    = 8081;

# These are used and set by Av4::TelnetOptions, by cmd_stats in Av4::Commands::Basic
# and shown when the mud terminates; hence they're 'our' vars.
our $mud_chars_sent         = 0;    # characters sent by mud
our $mud_chars_sent_nonmccp = 0;    # how many of these weren't compressed
our $mud_chars_sent_mccp    = 0;    # how many of these were compressed
our $mud_data_sent          = 0;    # data effectively sent
our $mud_data_sent_nonmccp  = 0;    # data sent uncompressed
our $mud_data_sent_mccp     = 0;    # data sent compressed
our $mud_start              = 0;    # time_t the mud started
our $cmd_processed          = 0;    # for stats: how many commands (even unknown) were processed

# These (overridable with ->new() args) indicate how often the 'ticks' are executed:
# Values are expressed in seconds.
# - the "flush" tick flushes all buffers associated with connected sockets
# - the "commands" tick iterates through all entities' queues and executes commands
# - the "players" tick saves info about how many players are online at that time
# - the "mobiles" tick may or may not have mobs execute actions (AI)
# - the "area" tick is supposed to reset (parts of) an area, and is not currently implemented.
our $sec_tick_flush    = 0.075;     # Buffers are flushed at each of this ticks
our $sec_tick_commands = 0.15;      # Commands are executed with delay is 0, delay is decremented every $sec_tick_commands seconds
our $sec_tick_mobiles  = 3.85;      # Mobiles execute actions (or not) every $sec_tick_mobiles seconds
our $sec_tick_players  = 0.50;      # Saves info about how many players are online at that date/time
our $sec_tick_area     = 59.35;     # Area-specific resets etc. happen every $sec_tick_area seconds

# For statistics purposes, these record the time_t a tick happened, and how long it took.
# Each of these arrays' members is a [ time, tv_interval ] of a tick which occurred.
our @delta_tick_commands;
our @delta_tick_flush;
our @delta_tick_players;

# The welcome banner (from a specific help page) is calculated and ansified once at
# startup, and then kept in this variable. There is no need to have it ansified at
# every single connection.
our $mud_welcome_banner = "Hello\r\n";

# The mud server -- in a way, a singleton although not really one..
our $server = undef;

# To speed up lookups, $users_by_handle{ anyevent handle } = $user;
our %users_by_handle;

# Used by "delegated" commands (so far, only a test)
our $gearman = AnyEvent::Gearman::Client->new( job_servers => ['127.0.0.1'], );

# This condvar is used to terminate the MUD. When anything sends it anything,
# the MUD terminates and will display statistics about its execution.
our $quit_program = AE::cv;

# Creates a new object, mainly setting undefined variables to their correct
# defaults and configuring log4perl if the "fake" option is given.
sub new {
    my $class = shift;
    my $opts  = {@_};
    $opts->{fake} = 0 if ( !defined $opts->{fake} );
    if ( !$opts->{fake} ) {
        Log::Log4perl::init_and_watch( 'log.conf', 'HUP' );
    }
    else {
        my $conf = q{
            log4perl.category.Av4 = DEBUG, Screen
            log4perl.category.main.new_dispatch_command = TRACE, Screen
            log4perl.category.Av4.AreaParse = WARN, Screen
            log4perl.appender.Screen = Log::Log4perl::Appender::Screen
            log4perl.appender.Screen.stderr = 0
            log4perl.appender.Screen.layout = PatternLayout
            log4perl.appender.Screen.layout.ConversionPattern=%d %F:%L %M %p %m%n
        };
        Log::Log4perl::init( \$conf );
    }
    $opts->{areadir}  = 'areas'    if ( !defined $opts->{areadir} );
    my $self = {};
    $listen_address    = $opts->{listen_address} if ( defined $opts->{listen_address} );
    $listen_port       = $opts->{listen_port}    if ( defined $opts->{listen_port} );
    $sec_tick_flush    = $opts->{tick_flush}     if ( defined $opts->{tick_flush} );
    $sec_tick_commands = $opts->{tick_commands}  if ( defined $opts->{tick_commands} );
    $sec_tick_mobiles  = $opts->{tick_mobiles}   if ( defined $opts->{tick_mobiles} );
    $self->{areadir}   = $opts->{areadir};
    return bless $self, $class;
}

# Actually runs the MUD. This needs called if you actually want to run the
# thing. It also performs the startup stuff (loading areas etc) and displays
# execution statistics at the end. Stuff like this should probably be moved
# to Av4::Server.
sub run {
    my $self = shift;
    $server = Av4::Server->new(
        areas => Av4::AreaParse::parse_areas_from_dir( $self->{areadir} ),
        helps => $Av4::AreaParse::helps,
    );
    warn "Parsed areas from dir  '$self->{areadir}'\n";
    warn "  -- areas parsed: " . scalar @{ $server->areas } . "\n";
    warn "  -- helps parsed: " . scalar @{ $server->helps } . "\n";
    my $banner = eval { Av4::AreaParse::areahelp( $server->helps, '__WELCOME__SCREEN__' )->data };
    $banner = "Hi, Welcome to the MUD!\r\n" if !defined $banner;
    $banner .= "\r\n";
    $mud_welcome_banner =
        sprintf( "%c%c%c", TELOPT_IAC, TELOPT_WILL, TELOPT_COMPRESS2 )
      . sprintf( "%c%c%c", TELOPT_IAC, TELOPT_DO,   TELOPT_TTYPE )
      . sprintf( "%c%c%c", TELOPT_IAC, TELOPT_DO,   TELOPT_NAWS )
      . sprintf( "%c%c%c", TELOPT_IAC, TELOPT_WILL, TELOPT_MSP )
      . sprintf( "%c%c%c", TELOPT_IAC, TELOPT_WILL, TELOPT_MXP )
      . '#$#mcp version: 2.1 to: 2.1' . "\r\n"
      . $banner;
    my $w = AE::signal( 'INT', sub { $quit_program->send('SIGINT') } );

    my $tick_buffers_flush = AE::timer( 1.0, $sec_tick_flush, \&tick_flush );
    warn "Tick flush called every $sec_tick_flush\n";

    my $tick_players = AE::timer( 1.0, $sec_tick_players, \&tick_players );
    warn "Tick players called every $sec_tick_players\n";

    my $tick_commands = AE::timer( 1.0, $sec_tick_commands, \&tick_commands );
    warn "Tick commands removes $sec_tick_commands each run\n";

    my $tick_mobiles = AE::timer( 1.0, $sec_tick_mobiles, \&tick_mobiles );
    $mud_start = [gettimeofday];

    # Load mobs from areas' resets
    {
        for my $area ( @{ $server->areas } ) {
            for my $mob ( @{ $area->mobiles // [] } ) {
                if ( $mob->in_room ) {
                    $mob->server($server);
                    $mob->commands_dispatched( [] );
                    $mob->queue(               [] );
                    $mob->delay(0);
                    my $room = $Av4::Room::rooms{ $mob->in_room };
                    if ($room) {
                        $mob->move_to_room( $mob->in_room );
                    }
                    else {
                        warn "Mob vnum " . $mob->{vnum} . " has unknown in_room: " . $mob->in_room . "\n";
                    }
                }
                else {
                    warn "Mob vnum " . $mob->{vnum} . " has no in_room\n";
                }
            }
        }
    }

    # TEST - create some entities
    if (0) {
        my $start_room = $Av4::Room::rooms{37};
        for ( 1 .. 10 ) {
            my $ent = Av4::Entity::Mobile->new(
                Av4::Entity::Mobile->defaults,
                server              => $server,
                name                => 'Entity#' . $_,
                in_room             => 30 + int( rand(4) ),
                commands_dispatched => [],
                queue               => [],
            );
            push @{ $start_room->entities() }, $ent;
            push @{ $server->entities() },     $ent;
        }
    }

    warn sprintf( "Listening on %s port %s\n", ( $listen_address // '*' ), $listen_port );
    if ( exists $INC{'Devel/NYTProf.pm'} ) {
        warn '-' x 72, "\nProfiling enabled...\n", '-' x 72, "\n";
        DB::enable_profile();
    }

    $listen_address = '::' if !defined $listen_address;
    tcp_server(
        $listen_address,
        $listen_port,
        \&server_accept_cb,
        sub {
            my ( $fh, $thishost, $thisport ) = @_;
            warn( "\e[32mTCP ready on address " . ( $listen_address // '*' ) . " port $thisport\e[0m\n" );
        }
    );

    # Everything "stops" here and AnyEvent does its thing, until something or
    # somebody does a $quit_program->send, at which point the rest of the program
    # here resumes, mainly displaying statistics about its execution.
    my $shutdown_by = $quit_program->recv;

    if ( exists $INC{'Devel/NYTProf.pm'} ) {
        DB::disable_profile();
        warn '-' x 72, "\nProfiling disabled...\n", '-' x 72, "\n";
    }

    # Statistics are now displayed:
    my $mud_uptime = tv_interval( $mud_start, [gettimeofday] );
    warn "\n\nShut down by $shutdown_by\n";
    warn sprintf( "MUD chars sent:         %20lu (%20.2f b/s)\n",   $mud_chars_sent,         $mud_chars_sent / $mud_uptime );
    warn sprintf( "MUD chars sent !mccp:   %20lu (%20.2f b/s)\n",   $mud_chars_sent_nonmccp, $mud_chars_sent_nonmccp / $mud_uptime );
    warn sprintf( "MUD chars sent mccp:    %20lu (%20.2f b/s)\n",   $mud_chars_sent_mccp,    $mud_chars_sent_mccp / $mud_uptime );
    warn sprintf( "MUD data sent:          %20lu (%20.2f KiB/s)\n", $mud_data_sent,          $mud_data_sent / 1024 / $mud_uptime );
    warn sprintf( "MUD data sent !mccp:    %20lu (%20.2f KiB/s)\n", $mud_data_sent_nonmccp,  $mud_data_sent_nonmccp / 1024 / $mud_uptime );
    warn sprintf( "MUD data sent mccp:     %20lu (%20.2f KiB/s)\n", $mud_data_sent_mccp,     $mud_data_sent_mccp / 1024 / $mud_uptime );
    warn sprintf( "Processed %d commands   in %d seconds: %2.2f commands/second\n", $cmd_processed, $mud_uptime, ( $cmd_processed / $mud_uptime ) );
    warn sprintf( "Memcached hits:         %d\n", $Av4::Utils::memcached_hits )   if $Av4::Utils::memcached_hits or $Av4::Utils::memcached_misses;
    warn sprintf( "Memcached misses:       %d\n", $Av4::Utils::memcached_misses ) if $Av4::Utils::memcached_hits or $Av4::Utils::memcached_misses;
    warn sprintf( "Memoized hits:          %d\n", $Av4::Utils::memoized_hits )    if $Av4::Utils::memoized_hits  or $Av4::Utils::memoized_misses;
    warn sprintf( "Memoized misses:        %d\n", $Av4::Utils::memoized_misses )  if $Av4::Utils::memoized_hits  or $Av4::Utils::memoized_misses;
    eval "use Devel::Size;";
    warn sprintf( "Memoized D::Size bytes: %d\n", Devel::Size::total_size( \%Av4::Utils::ansify_cache ) ) if ( !$@ );
    {
        open my $fh, '>', 'tick_players.csv';
        print $fh "tick,players\n";
        for ( 0 .. $#delta_tick_players ) {
            print $fh sprintf( "%s,%d\n", @{ $delta_tick_players[$_] } );
        }
        close $fh;
    }
    warn "Tick commands: " . scalar @delta_tick_commands, "\n";
    my $total = 0;
    map { $total += $_->[1] } @delta_tick_commands;
    my $min = $delta_tick_commands[0]->[1];
    my $max = $delta_tick_commands[0]->[1];
    {
        open my $fh, '>', 'tick_commands.csv';
        print $fh "tick,seconds\n";
        for ( 0 .. $#delta_tick_commands ) {
            print $fh sprintf( "%s,%.6f\n", @{ $delta_tick_commands[$_] } );
        }
        close $fh;
    }
    map { $min = $_->[1] if $_->[1] < $min; $max = $_->[1] if $_->[1] > $max; } @delta_tick_commands;

    # Time taken by command, from Av4::Command
    {
        warn "Time taken by command:\n";
        for my $command ( sort keys %Av4::Command::time_taken_by_command ) {
            my $min        = $Av4::Command::time_taken_by_command{$command}->[0]->[1];
            my $max        = $Av4::Command::time_taken_by_command{$command}->[0]->[1];
            my $total      = 0;
            my $min_size   = 0;
            my $max_size   = 0;
            my $total_size = 0;
            my $n_commands = 0;
            for ( @{ $Av4::Command::time_taken_by_command{$command} } ) {
                $n_commands++;
                $min = $_->[1] if $_->[1] < $min;
                $max = $_->[1] if $_->[1] > $max;
                $total += $_->[1];
                if ( $_->[2] ) {
                    $min_size = $_->[2] if !$min_size;
                    $min_size = $_->[2] if $_->[2] < $min_size;
                    $max_size = $_->[2] if $_->[2] > $max_size;
                    $total_size += $_->[2];
                }
            }
            warn sprintf(
                "  Command %-10s took min %.6f max %.6f median %.6f min size %-8s max size %-8s median size %s\n",
                $command, $min, $max, $total / $n_commands,
                $min_size, $max_size, $total_size / $n_commands
            );
        }
    }

    warn sprintf( "Tick commands median: %.6f\n", ( $total / scalar @delta_tick_commands ) );
    warn sprintf( "Tick commands min:    %.6f\n", $min );
    warn sprintf( "Tick commands max:    %.6f [vs max $sec_tick_commands] %s\n", $max, $max > $sec_tick_commands ? ' [WARNING]' : '[OK]' );
    warn "Tick flush: " . scalar @delta_tick_flush, "\n";
    $total = 0;
    map { $total += $_->[1] } @delta_tick_flush;
    $min = $delta_tick_flush[0]->[1];
    $max = $delta_tick_flush[0]->[1];
    {
        open my $fh, '>', 'tick_flush.csv';
        print $fh "tick,seconds\n";
        for ( 0 .. $#delta_tick_flush ) {
            print $fh sprintf( "%s,%.6f\n", @{ $delta_tick_flush[$_] } );
        }
        close $fh;
    }
    map { $min = $_->[1] if $_->[1] < $min; $max = $_->[1] if $_->[1] > $max; } @delta_tick_flush;
    warn sprintf( "Tick flush median: %.6f\n", ( $total / scalar @delta_tick_flush ) );
    warn sprintf( "Tick flush min:    %.6f\n", $min );
    warn sprintf( "Tick flush max:    %.6f [vs max $sec_tick_flush] %s\n", $max, $max > $sec_tick_flush ? ' [WARNING]' : '[OK]' );

    # Have a nice day!
    exit 0;
}

# This gets called whenever a new client connects to the server.
# A new AnyEvent::Handle is created for the connection, as well as
# a Av4::Entity::Player which is added to the global list of MUD
# entities connected. The MUD banner is sent, and the player's
# callback on input is set so they will actually able to do something.
sub server_accept_cb {
    my ( $fh, $host, $port ) = @_;
    my $handle;
    $handle = new AnyEvent::Handle(

        #autocork => 1,
        fh       => $fh,
        on_error => \&client_error,
        on_eof   => \&client_quit,
    );
    my $new_user = Av4::Entity::Player->new(
        Av4::Entity::Player->defaults,
        id                     => $handle,
        server                 => $server,
        host                   => $host,
        port                   => $port,
        queue                  => [],
        mcp_packages_supported => {},
        mcp_authentication_key => '',
        commands_dispatched    => [],
    );
    $users_by_handle{ $handle } = $new_user;
    $new_user->telopts( Av4::TelnetOptions->new( user => $new_user ) );
    push @{ $server->clients },  $new_user;
    push @{ $server->entities }, $new_user;

    # warn "Connection from $host:$port (H $handle, U $new_user) -- " .
    #   scalar @{ $server->clients } . " clients / " . scalar @{ $server->entities } .
    #   " entities online now\n";
    $Av4::Commands::Basic::wholist = undef;    # invalidate who list
    $handle->push_write($mud_welcome_banner);
    $handle->on_read( \&client_read );
    $new_user->prompt();
    return;
}

# This gets called whenever a client has sent something. Various error
# situations are resolved here either by "just" purging the client, or
# by making other clients aware the client is quitting.
# SPAM is handled here (a client having more than 80 commands in their queue).
sub client_read {
    my $data = $_[0]->rbuf;
    $_[0]->rbuf = '';
    my $user = $users_by_handle{ $_[0] };
    die "Cant find user $_[0] in users_by_handle!" if ( !defined $user );

    #__data_log( 'Received from', $client, $data );    # ONLY FOR DEBUG!
    eval { $data = $user->received_data($data); };
    if ($@) {
        warn("Quitting client $_[0]: $@\n");
        delete $users_by_handle{ $_[0] };
        $_[0]->destroy;
        $user->id->destroy;
        $server->clients(  [ grep { defined $_ && $_->id != $_[0] } @{ server->clients } ] );
        $server->entities( [ grep { defined $_ && $_->id != $_[0] } @{ server->entities } ] );
        return;
    }
    $server->inbuffer->{ $_[0] } .= $data;
    while ( $server->inbuffer->{ $_[0] } =~ s/(.*\n)// ) {
        my $typed = defined $1 ? $1 : '';
        $typed =~ s/[\x0D\x0A]//gm;
        if ( @{ $user->queue } > 80 && $typed !~ /^\s*quit/ ) {
            $typed = 'quit';
            $user->broadcast(
                $_[0],
                "$Av4::Utils::ANSI{'&W'}$user $Av4::Utils::ANSI{'&G'}quits due to spamming\n\r",
                "$Av4::Utils::ANSI{'&W'}You $Av4::Utils::ANSI{'&G'}quit due to SPAMMING!\n\r",
                1,    # send prompt to others
            );
            warn("Client $_[0] SPAMMING (queue>80) ==> OUT!\n");
            delete $users_by_handle{ $_[0] };
            $user->queue( ['quit'] );
            $server->inbuffer->{ $_[0] } = '';
            $user->id->destroy;
            $server->clients(  [ grep { defined $_ && $_->id != $_[0] } @{ $server->clients } ] );
            $server->entities( [ grep { defined $_ && $_->id != $_[0] } @{ $server->entities } ] );
        }
        push @{ $user->queue }, $typed;
    }

    # commands are now dispatched via tick_commands
}

# This gets called when a client has received an error. The client is purged
# from the server and the server goes their merry way.
sub client_error {
    #my ($user) = grep { defined $_ && $_->id == $_[0] } @{ $server->clients };
    my $user = $users_by_handle{ $_[0] };
    my $name = $user ? $user->name : $_[0];
    if ($user) {
        $user->queue( [] );
        if ( $user->in_room ) {

            # Player is no longer in the room
            $user->remove_from_room();
        }
    }
    delete $users_by_handle{ $_[0] };
    $server->clients(  [ grep { defined $_ && $_->id != $_[0] } @{ $server->clients } ] );
    $server->entities( [ grep { defined $_ && $_->id != $_[0] } @{ $server->entities } ] );
    $_[0]->destroy();
    $Av4::Commands::Basic::wholist = undef;    # invalidate who list
    $user->broadcast(
        $_[0],
        "$Av4::Utils::ANSI{'&W'}$name $Av4::Utils::ANSI{'&G'}quits the MUD due to errors $_[2]\n\r",
        '',
        1,                                     # send prompt to others
    );
    warn("$name ($_[0]) quits due to errors: $_[2]\n");
}

# This gets called whenever a client quits.
sub client_quit {
    my $user = $users_by_handle{ $_[0] };
    my $name = $user ? $user->name : $_[0];
    if ($user) {
        $user->queue( [] );
        if ( $user->in_room ) {

            # Player is no longer in the room
            $user->remove_from_room();
        }
    }
    delete $users_by_handle{ $_[0] };
    $server->clients(  [ grep { defined $_ && $_->id != $_[0] } @{ $server->clients } ] );
    $server->entities( [ grep { defined $_ && $_->id != $_[0] } @{ $server->entities } ] );
    $_[0]->destroy();
    $Av4::Commands::Basic::wholist = undef;    # invalidate who list
    $user->broadcast(
        $_[0],
        "$Av4::Utils::ANSI{'&W'}$name $Av4::Utils::ANSI{'&G'}quits the MUD\n\r",
        '',
        1,                                     # send prompt to others
    );
    warn("$name ($_[0]) quits the MUD\n");
}

# Broadcast a message to -all- entities (not "just" clients)
sub broadcast {
    my ( $by, $message, $sendprompt ) = @_;
    ## $log->info("(by $by) Server broadcast: $message");
    $sendprompt = 0 if ( !defined $sendprompt );

    # Send it to everyone.
    foreach my $entity ( @{ $server->entities } ) {
        next if ( !defined $entity );
        $entity->print($message);
        $entity->prompt if ($sendprompt);
    }
}

# Players tick: records the amount of connected clients every tick
sub tick_players {
    my $t0      = [gettimeofday];
    my $clients = scalar grep { defined $_ } @{ $server->clients };
    my $time    = time;
    push @delta_tick_players, [ $time, $clients ];
}

# Flush tick: sends buffered data to all clients who need their buffers flushed.
sub tick_flush {
    my $t0 = [gettimeofday];
    my @clients = grep { defined $_ } @{ $server->clients };
    $server->clients( \@clients );
    foreach my $client (@clients) {
        next unless $client->buffer;
        $client->telopts->send_data( \$client->buffer );
        $client->buffer(undef);

        #$client->buffer_last_flushed(time);
    }
    my $time = time;
    push @delta_tick_flush, [ $time, tv_interval( $t0, [gettimeofday] ) ];
    warn "**** TICK FLUSH LAG *** $delta_tick_flush[-1]->[1] vs $sec_tick_flush\n" if $delta_tick_flush[-1]->[1] > $sec_tick_flush;
}

# Commands tick: decreases each entity's "delay" by one unit, and executes
# the first plausible command if/when an entity is not delayed.
# NOTA BENE: MCP commands (chiefly) cause this to execute more than one command
# per tick per entity.
sub tick_commands {
    my $t0 = [gettimeofday];
    my @entities = grep { defined $_ } @{ $server->entities };
    $server->entities( \@entities );
    foreach my $entity ( @{ $server->entities } ) {
        next if ( !defined $entity );
        my $was_delayed = 0;
        if ( $entity->delay > 0 ) {
            $was_delayed = 1;
            $entity->delay(
                  $entity->delay - $sec_tick_commands >= 0
                ? $entity->delay - $sec_tick_commands
                : 0
            );
        }
        my ( $dispatched, $redispatch ) = $entity->dispatch_command();
        if ( defined $dispatched ) {
            push @{ $entity->commands_dispatched }, $dispatched;
        }
        $entity->prompt() if ( $was_delayed && !$entity->delay );
        redo if ( defined $redispatch && $redispatch );
    }
    my $time = time;
    push @delta_tick_commands, [ $time, tv_interval( $t0, [gettimeofday] ) ];
    warn "**** TICK COMMANDS LAG *** $delta_tick_commands[-1]->[1] vs $sec_tick_commands\n" if $delta_tick_commands[-1]->[1] > $sec_tick_commands;
    if ( scalar @delta_tick_commands >= 800 ) {
        Av4->broadcast( '** SHUTTING DOWN AFTER 800 COMMANDS TICKS **', 0 );    # no prompt
        tick_flush();    # Have all clients receive the previous message
        $quit_program->send("Shut down after 800 command ticks");
    };
}

# Mobiles tick: the monsters' AI.
# Currently monsters just send a random command, similarly to how the fuzzier works.
sub tick_mobiles {
    my @entities = grep { defined $_ && ref $_ eq 'Av4::Entity::Mobile' } @{ $server->entities };
    foreach my $entity (@entities) {
        $entity->random_command();
    }
}

# Utility function to shutdown the MUD: broadcasts the shutdown and shuts it down.
sub shutdown {
    my ( $self, $bywho ) = @_;
    my $shutdown_by = $bywho->id;
    broadcast( $bywho->id, "$shutdown_by initiated shutdown...\n", 0 );
    tick_flush();    # Have all clients receive the previous message
    $quit_program->send($shutdown_by);
}

1;
