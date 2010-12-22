package Av4::User;
use strict;
use warnings;
use Av4;
use Av4::Commands;
use Av4::TelnetOptions;
use Av4::Utils qw/get_logger ansify/;
use YAML;

use Class::XSAccessor {
    constructor => '_new',
    accessors => [qw/server id state name telopts mcp_authentication_key mcp_packages_supported commands commands_dispatched queue delay/],
};

sub new {
    my $class = shift;
    my $self = $class->_new(
        # defaults
        server => {},
        id => '',
        state => 0,
        name => '',
        mcp_authentication_key => '',
        mcp_packages_supported => {},
        commands => Av4::Commands->new(),
        commands_dispatched => [],
        queue => [],
        delay => 0,
        # wanted options
        @_,
    );
    $self->telopts(Av4::TelnetOptions->new( user => $self )); # FIXME may have been given in params
    $self;
}

our %states = (
    CONNECTED  => 0,
    PLAYING    => 1,
);
our $STATE_PLAYING = $states{PLAYING};
our %state_name = reverse %states;
our %state_dispatch = (
    0 => \&state_get_name,
);

sub received_data {
    my ( $self, $data ) = @_;
    return $self->telopts->analyze($data);
}

sub prompt {
    my $self = shift;
    return sprintf("\r\n(%s) (delay %d) > \r\n", $self->name, $self->delay) if $self->state == $STATE_PLAYING;
    if ( $state_name{$self->state} eq 'CONNECTED' ) {
        return sprintf("\r\nHow would you like to be known as? > \r\n");
    }
    my $log = get_logger();
    $log->error("User $self in unknown state " . $self->state());
    return 'BUG> ';
}

sub print {
    my $self = shift;
    return unless defined $self->id;
    #$self->id->push_write($_) for @_;
    $self->telopts->send_data(\$_) for @_;
    #my $out = join( '', @_ );
    #$self->telopts->send_data(\$out);
}

sub broadcast {
    my ( $self, $client, $message, $selfmessage, $sendprompt, $sendtoself ) = @_;
    $sendprompt  = 0        if ( !defined $sendprompt );
    $sendtoself  = 1        if ( !defined $sendtoself );
    $selfmessage = $message if ( !defined $selfmessage );
    my $log = get_logger();
    $log->info("Broadcasted from $client: $message");

    #my $a_selfmessage = ansify( $selfmessage );
    #my $a_message     = ansify( $message     );

    # Send it to everyone.
    foreach my $user ( @{ $self->server->clients } ) {
        next if ( !defined $user );
        next if ( !$sendtoself && $user->id == $client );
        next if ( $user->state != $STATE_PLAYING );
        #$log->info("Sending shout to client $user");
        if ( $user->id == $client ) {
            $user->print( $selfmessage );
        } else {
            $user->print( $message );
            $user->print( $user->prompt ) if ($sendprompt);
        }
        #$kernel->yield( event_write => $user->id );
    }
}

sub dumpqueue {
    my $user   = shift;
    my $ansify = shift;
    my $out    = '';
    return $out if ( !defined $user );
    $ansify = 0 if ( !defined $ansify );
    $out .= "Queue for user $user:\n";
    foreach my $cmdno ( 0 .. $#{ $user->queue } ) {
        my $command = defined $user->queue->[$cmdno] ? $user->queue->[$cmdno] : 'N/A';
        my ( $cmd, $args ) = split( /\s/, $command, 2 );
        $cmd  = $command if ( !defined $cmd );
        $args = ''       if ( !defined $args );
        my $known = $user->commands->exists($cmd) ? 1 : 0;
        my $delays = 'n/a';
        $delays = $user->commands->cmd_get($cmd)->delays if ($known);
        my $priority = 'n/a';
        $priority = $user->commands->cmd_get($cmd)->priority if ($known);
        $out .= sprintf(
            "%s %s %s %s %s\n",
            $ansify ? ansify( sprintf( "&R#%-2d",  $cmdno ) )  : sprintf( "#%-2d",  $cmdno ),
            $ansify ? ansify( sprintf( "&cD %-2s", $delays ) ) : sprintf( "D %-2s", $delays ),
            $ansify
            ? ansify( sprintf( "&gPRI %-2s", $priority ) )
            : sprintf( "PRI %-2s", $priority ),
            $ansify ? ( ansify( sprintf( "&W[%s&W]", $known ? '&gKNOWN' : '&rUNKNOWN' ) ) )
            : ( $known ? '[KNOWN]' : '[UNKNOWN]' ),
            $ansify ? ansify("&W$command") : $command,
        );
    }
    return $out;
}

sub state_get_name {
    my ( $self, $kernel ) = @_;
    my $log = get_logger(1);
    my $name = shift @{$self->queue};
    chomp($name);
    $name =~ s/[\x0D\x0A]+//g;
    $self->name($name);
    $self->state( $self->state + 1 );
    $self->print( sprintf("\n\r%s %s\r\n",ansify("&YYou will be known as"),ansify("&c'&W$name&^&c'")) );
    $self->print( sprintf "\33]0;Av4 - %s\a", "\Q$name\E" ); # sets terminal title
    $self->print("\r\n");
    $self->broadcast(
        $self->id,
        ansify("&W\Q$name\E").' '.ansify("&Ghas entered the MUD") . "\n\r",
        ansify("&WYou") . ' ' . ansify("&ghave entered the MUD") . ansify("\n\r"),
        1,    # send prompt to others
    );
    $self->print( $self->prompt );
    return;
}

# First, removes all unknown commands from the list and alerts the user
# If the user isn't delayed, executes the most prioritized command
# If the user is delayed, executes the most prioritized non-delaying command
sub dispatch_command {
    my ( $self ) = @_;
    my $log = get_logger(1);
    #$log->debug("Dispatching command for $self");
    if ( !@{ $self->queue } ) {
        #$log->debug("No commands in queue for $self");
        return;
    }
    #$log->info( "User $self commands in queue: " . dumpqueue($self) );

    # weeds out empty and unknown commands
    {
        my @cmds = grep { defined $_ && $_ !~ /^\s*$/ } @{ $self->queue };
        $self->queue( \@cmds );
    }

    my $sub = $state_dispatch{ $self->state } // 0;
    if ( $sub ) {
        return $sub->($self);
    }

    #$log->info( "Weeded $self commands in queue: " . dumpqueue($self) );
    my $highest_priority_delaying    = -999;
    my $highest_priority_nondelaying = -999;
    foreach my $lineno ( 0 .. $#{ $self->queue } ) {
        if ( $self->queue->[$lineno] =~ /^\e\[\dz/ )
        {
            Av4::Commands::MXP::cmd_mxp_option( $self->id, $self, $self->queue->[$lineno] );
            delete $self->queue->[$lineno];
            next;
        }
        my ( $cmd, $args ) = split( /\s/, $self->queue->[$lineno], 2 );
        #$log->info(
        #    "Queue line $lineno: cmd >",
        #    defined $cmd              ? $cmd  : 'undef',
        #    '< args >', defined $args ? $args : 'undef', '<',
        #);
        $cmd  = $self->queue->[$lineno] if ( !defined $cmd );
        $cmd  = lc $cmd;
        $args = '' if ( !defined $args );
        $self->print('');
        if ( !$self->commands->exists($cmd) ) {
            $self->print( ansify("\n\r&RUnknown command &c'&W$cmd&^&c'\r\n"), $self->prompt, );
            #$log->info("Re-weeding: removing command $cmd from list since it's unknown");
            delete $self->queue->[$lineno];
            next;
        }
        #$log->debug("Checking command's delays and priority for $cmd");
        if ( $self->commands->cmd_get($cmd)->delays ) {    # this command delays
            #$log->trace("Command $cmd delays");
            if ( $self->commands->cmd_get($cmd)->priority() > $highest_priority_delaying ) {
                #$log->trace( "Command $cmd delays and has highest priority so far, setting highest_priority_delaying to ",
                #    $self->commands->cmd_get($cmd)->priority(),
                #);
                $highest_priority_delaying = $self->commands->cmd_get($cmd)->priority();
            }
        } else {
            #$log->trace("Command $cmd does not delay");
            if ( $self->commands->cmd_get($cmd)->priority() > $highest_priority_nondelaying ) {
                #$log->trace( "Command $cmd does not delay and has highest priority so far, setting highest_priority_nondelaying to ",
                #    $self->commands->cmd_get($cmd)->priority(),
                #);
                $highest_priority_nondelaying = $self->commands->cmd_get($cmd)->priority();
            }
        }
    }
    #$log->info( "Re-Weeded $self commands: " . dumpqueue($self) );
    #$log->debug( "Highest priority delaying    : ", $highest_priority_delaying );
    #$log->debug( "Highest priority NON delaying: ", $highest_priority_nondelaying );
    my $highest_priority =
      $self->delay ? $highest_priority_nondelaying
      : (
          $highest_priority_nondelaying > $highest_priority_delaying ? $highest_priority_nondelaying
        : $highest_priority_delaying
      );
    #$log->debug(
    #    "Since the user is ",
    #    $self->delay ? '' : 'NOT ',
    #    'delaying, chosen priority ',
    #    $highest_priority
    #);

    #$log->debug("Finding and executing command of priority $highest_priority..");
    foreach my $lineno ( 0 .. $#{ $self->queue } ) {
        next if ( !defined $self->queue->[$lineno] );
        my ( $cmd, $args ) = split( /\s/, $self->queue->[$lineno], 2 );
        $cmd  = $self->queue->[$lineno] if ( !defined $cmd );
        $cmd  = lc $cmd;
        $args = '' if ( !defined $args );

        # skip if the user is delayed and this command delays
        next if ( $self->delay && $self->commands->cmd_get($cmd)->delays );
        if ( $self->commands->cmd_get($cmd)->priority() >= $highest_priority ) {
            #$log->info("Dispatching client $self with command (#$lineno) $cmd args $args");
            #my $delay = $self->commands->cmd_get($cmd)->exec( $kernel, $self->id, $self, $args );
            my $delay = $self->commands->cmd_get($cmd)->exec( $self->id, $self, $args );
            $Av4::cmd_processed++;
            $self->delay( $self->delay + $delay );

            $self->print( $self->prompt ) if ( $cmd !~ /^\s*quit\s*$/ );
            $log->debug("***DISPATCHED/DELETING $cmd $args");

            #push @effectively_dispatched, "$cmd $args";
            my $command_dispatched = $self->queue->[$lineno];
            delete $self->queue->[$lineno];
            # weeds out empty and unknown commands
            {
                my @cmds = grep { defined $_ && $_ !~ /^\s*$/ } @{ $self->queue };
                $self->queue( \@cmds );
            }
            return (
                $command_dispatched,
                $cmd =~ /^\#\$\#mcp/ ? 1 : 0,    # redispatch if MCP command (negotiation)
            );
        }
    }

    #$log->error("No command dispatched for client $self");

    #$self->print( $self->prompt );
    return;
}

1;
