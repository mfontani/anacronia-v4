package Av4::Entity::Player;
use strict;
use warnings;

use base 'Av4::Entity';

require Av4::TelnetOptions;
use Av4::Utils;    # for ANSI
use Av4::Telnet qw/
  TELOPT_IAC TELOPT_GA
  /;

sub defaults {
    (
        Av4::Entity->defaults,
        is_player => 1,
        state     => 0,
        in_room   => 30,
    );
}

use Class::XSAccessor {
    constructor => 'new',
    accessors   => [
        qw/
          buffer
          buffer_last_flushed
          telopts
          mcp_authentication_key
          mcp_packages_supported
          host
          port
          /
    ],
};

our %state_dispatch = ( 0 => \&state_get_name, );

sub received_data {
    $_[0]->telopts->analyze( $_[1] );
}

sub prompt {
    my $t = $_[0]->telopts;

    #if ($_[0]->buffer) {
    #    $t->send_data( \$_[0]->buffer );
    #    $_[0]->buffer(undef);
    #    $_[0]->buffer_last_flushed(time);
    #    return if $_[1]; # just flush buffer, no prompt (HACK - FIXME)
    #}
    #return $t->send_data(
    return $_[0]
      ->buffer( ( $_[0]->buffer // '' ) . sprintf( "\r\n\e[0m(%s) (delay %.1f) > %c%c\r\n", $_[0]->name, $_[0]->delay, TELOPT_IAC, TELOPT_GA, ) )
      if $_[0]->state == $Av4::Entity::STATE_PLAYING;

    #return $t->send_data(
    return $_[0]->buffer( ( $_[0]->buffer // '' ) . sprintf( "\r\nHow would you like to be known as? > %c%c\r\n", TELOPT_IAC, TELOPT_GA ) )
      if ( $Av4::Entity::state_name{ $_[0]->state } eq 'CONNECTED' );
    my $log = get_logger();
    $log->error( "User $_[0] in unknown state " . $_[0]->state() );

    #return $t->send_data(\'BUG> ');
    return $_[0]->buffer( ( $_[0]->buffer // '' ) . 'BUG> ' );
}

sub print_raw {
    my $self = shift;
    $self->telopts->send_data( \$_ ) for @_;
    $self->prompt(1) if ( $self->buffer_last_flushed && $self->buffer_last_flushed < time - 1 );
}

sub print {
    $_[0]->buffer('') unless defined $_[0]->buffer;
    my $self = shift;
    for my $s (@_) {
        $self->buffer( $self->buffer . $s );
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
        my $known  = Av4::Commands->cmd_exists($cmd) ? 1 : 0;
        my $delays = 'n/a';
        my $CMD    = Av4::Commands->cmd_get($cmd);
        $delays = $CMD->delays if ($known);
        my $priority = 'n/a';
        $priority = $CMD->priority if ($known);
        $out .= sprintf(
            "%s %s %s %s %s\n",
            $ansify ? sprintf( "$Av4::Utils::ANSI{'&R'}#%-2d",  $cmdno )  : sprintf( "#%-2d",  $cmdno ),
            $ansify ? sprintf( "$Av4::Utils::ANSI{'&c'}D %-2s", $delays ) : sprintf( "D %-2s", $delays ),
            $ansify
            ? sprintf( "$Av4::Utils::ANSI{'&g'}PRI %-2s", $priority )
            : sprintf( "PRI %-2s",                        $priority ),
            $ansify
            ? sprintf( "$Av4::Utils::ANSI{'&W'}\[%s$Av4::Utils::ANSI{'&W'}]",
                $known
                ? "$Av4::Utils::ANSI{'&g'}KNOWN"
                : "$Av4::Utils::ANSI{'&r'}UNKNOWN" )
            : ( $known ? '[KNOWN]' : '[UNKNOWN]' ),
            $ansify ? "$Av4::Utils::ANSI{'&W'}$command" : $command,
        );
    }
    return $out;
}

sub state_get_name {
    my ( $self, $kernel ) = @_;
    my $name = shift @{ $self->queue };
    chomp($name);
    $name =~ s/[\x0D\x0A]+//g;
    $self->name($name);
    $self->state( ( $self->state // 0 ) + 1 );
    $self->print(
            "\r\n"
          . $Av4::Utils::ANSI{'&Y'}
          . "You will be known as"
          . $Av4::Utils::ANSI{'&c'} . "'"
          . $Av4::Utils::ANSI{'&W'}
          . $name
          . $Av4::Utils::ANSI{'&c'} . "'"
          . $Av4::Utils::ANSI{'&^'}
          . sprintf( "\33]0;Av4 - %s\a", "\Q$name\E" )    # sets terminal title
          . "\r\n"
    );

    #warn "Connection from " . $self->host . ':' . $self->port . ' (H ' . $self->id . ', U ' . $self . ') chose name ' . $name . "\n";
    my $new_room = $Av4::Room::rooms{ $self->in_room };
    push @{ $new_room->entities() }, $self;
    $new_room->broadcast(
        $self,
        $Av4::Utils::ANSI{'&W'}
          . "\Q$name\E "
          . $Av4::Utils::ANSI{'&G'}
          . "has entered the MUD"
          . $Av4::Utils::ANSI{'&^'} . "\r\n",
        $Av4::Utils::ANSI{'&W'} . "You "
          . $Av4::Utils::ANSI{'&g'}
          . "have entered the MUD"
          . $Av4::Utils::ANSI{'&^'} . "\r\n",
        1,    # send prompt to others
    );
    push @{ $self->queue }, 'look';
    return;
}

# First, removes all unknown commands from the list and alerts the user
# If the user isn't delayed, executes the most prioritized command
# If the user is delayed, executes the most prioritized non-delaying command
sub dispatch_command {
    my ($self) = @_;

    my @queue = @{ $self->queue };
    return unless @queue;

    #@queue = grep { defined $_ && $_ !~ /^\s*$/ } @queue; # Unneeded

    # OK if this takes some msec as it's really only called upon connection,
    # the rest of the time the time spent here is negligible.
    if ( my $sub = $state_dispatch{ $self->state } ) {
        return $sub->($self);
    }

    my $highest_priority_delaying    = -999;
    my $highest_priority_nondelaying = -999;
    foreach my $lineno ( 0 .. $#queue ) {
        if ( $queue[$lineno] =~ /^\e\[\dz/ ) {
            Av4::Commands::MXP::cmd_mxp_option( $self->id, $self, $queue[$lineno] );
            delete $queue[$lineno];
            next;
        }
        my ( $cmd, $args ) = split( /\s/, $queue[$lineno], 2 );
        $cmd = $queue[$lineno] if ( !defined $cmd );
        $cmd = lc $cmd;
        $args //= '';

        #my $CMD = Av4::Commands->cmd_get($cmd);   # spent  2.82ms making 716 calls to Av4::Commands::cmd_get, avg 4µs/call
        my $CMD = $Av4::Commands::commands{$cmd};
        if ( !$CMD ) {
            $self->print(
                "\r\n$Av4::Utils::ANSI{'&R'}Unknown command $Av4::Utils::ANSI{'&c'}'$Av4::Utils::ANSI{'&W'}$cmd$Av4::Utils::ANSI{'&c'}'\r\n");
            $self->prompt;
            delete $queue[$lineno];
            $Av4::cmd_processed++;
            next;
        }
        if ( $CMD->delays ) {    # this command delays
            if ( $CMD->priority() > $highest_priority_delaying ) {
                $highest_priority_delaying = $CMD->priority();
            }
        }
        else {
            if ( $CMD->priority() > $highest_priority_nondelaying ) {
                $highest_priority_nondelaying = $CMD->priority();
            }
        }
    }

    my $highest_priority =
      $self->delay ? $highest_priority_nondelaying
      : (
          $highest_priority_nondelaying > $highest_priority_delaying ? $highest_priority_nondelaying
        : $highest_priority_delaying
      );

    foreach my $lineno ( 0 .. $#queue ) {
        next if ( !defined $queue[$lineno] );
        my ( $cmd, $args ) = split( /\s/, $queue[$lineno], 2 );
        $cmd = $queue[$lineno] if ( !defined $cmd );
        $cmd = lc $cmd;
        $args //= '';

        # skip if the user is delayed and this command delays
        #my $CMD = Av4::Commands->cmd_get($cmd); # spent  1.61ms making 703 calls to Av4::Commands::cmd_get, avg 2µs/call
        my $CMD = $Av4::Commands::commands{$cmd};
        next if ( $self->delay && $CMD->delays );
        if ( $CMD->priority() >= $highest_priority ) {
            my $delay = $CMD->exec( $self->id, $self, $args );
            $Av4::cmd_processed++;
            $self->delay( $self->delay + $delay );

            $self->prompt if ( $cmd !~ /^\s*quit\s*$/ );

            #$self->prompttimer(AnyEvent->timer( after => $self->delay, cb => sub { $self->prompt() })) if $self->delay;

            my $command_dispatched = $queue[$lineno];
            delete $queue[$lineno];

            # Remove the just-deleted line from the queue
            {
                my @cmds = grep { defined } @queue;
                $self->queue( \@cmds );
            }
            return (
                $command_dispatched,
                $cmd =~ /^\#\$\#mcp/ ? 1 : 0,    # redispatch if MCP command (negotiation)
            );
        }
    }
    my @cmds = grep { defined } @queue;
    $self->queue( \@cmds );

    return;
}

=head1 WARNING

After construction by calling C<-E<gt>new>, the following needs to be done:

    $self->telopts(Av4::TelnetOptions->new( user => $self ));

=cut

1;
