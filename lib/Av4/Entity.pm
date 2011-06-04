package Av4::Entity;
use strict;
use warnings;
use Av4::Utils qw/get_logger/;
use Av4::Commands;
use YAML;

our $last_id = 0;

sub defaults {
    (
        is_player => 0,
        id        => ++$last_id,
        state     => 1,
        name      => 'An unnamed entity',
        short     => 'An unnamed entity lays on the ground.',
        desc      => 'An unnamed entity cannot be described.',
        keywords  => [],
        delay     => 0,
        in_room   => 1,
    );
}
use Class::XSAccessor {
    constructor => 'new',
    accessors   => [
        qw/
          is_player
          state
          server
          id
          name
          keywords
          queue
          short
          short_ansi
          desc
          desc_ansi
          prompttimer
          commands_dispatched
          delay
          in_room
          /
    ],
};

our %states = (
    CONNECTED => 0,
    PLAYING   => 1,
);
our $STATE_PLAYING  = $states{PLAYING};
our %state_name     = reverse %states;
our %state_dispatch = ();

# By default, an entity doesn't hook to these
sub received_data { }
sub prompt        { }
sub print_raw     { }
sub print         { }
sub dumpqueue     { }

sub remove_from_room {
    my ( $self, $msg_leave_self, $msg_leave_others, $silently_self, $silently_others ) = @_;
    my $current_room = $Av4::Room::rooms{ $self->in_room };
    unless ($current_room) {
        warn "remove_from_room: invalid vnum " . $self->in_room;
        return;
    }
    $self->print($msg_leave_self) if ( $msg_leave_self && !$silently_self );
    $current_room->broadcast( $self, $msg_leave_others ) if $msg_leave_others && !$silently_others;
    $current_room->entities( [ grep { $_ ne $self } @{ $current_room->entities } ] );
    $current_room->clients( [ grep { $_ ne $self } @{ $current_room->clients } ] ) if ref $self eq 'Av4::Entity::Player';
    $self->in_room(0);
}

sub move_to_room {
    my ( $self, $to_vnum, $msg_leave_self, $msg_leave_others, $msg_enter_self, $msg_enter_others, $silently_self, $silently_others ) = @_;
    my $to_room = $Av4::Room::rooms{$to_vnum};
    unless ($to_room) {
        warn "move_to_room: invalid vnum $to_vnum";
        return;
    }
    $self->remove_from_room( $msg_leave_self, $msg_leave_others, $silently_self );
    push @{ $to_room->entities() }, $self;
    push @{ $to_room->clients() }, $self if ref $self eq 'Av4::Entity::Player';
    $self->in_room($to_vnum);
    $to_room->broadcast( $self, $msg_enter_others ) if $msg_enter_others && !$silently_others;
    $self->print($msg_enter_self) if ( $msg_enter_self && !$silently_self );
}

sub broadcast {
    my ( $self, $client, $message, $selfmessage, $sendprompt, $sendtoself ) = @_;
    $sendprompt  = 0        if ( !defined $sendprompt );
    $sendtoself  = 1        if ( !defined $sendtoself );
    $selfmessage = $message if ( !defined $selfmessage );

    # Send it to everyone.
    foreach my $entity ( @{ $self->server->clients } ) {    # ->entities lags :|
        my $id = $entity->id;
        next if ( !$sendtoself && $id == $self->id );
        next if ( $entity->state != $STATE_PLAYING );
        if ( $id == $self->id ) {
            $entity->print($selfmessage);
        }
        else {
            $entity->print($message);
            $entity->prompt if ($sendprompt);
        }
    }
}

sub dispatch_command {
    my $self  = shift;
    my @queue = @{ $self->queue };
    @queue = grep { defined $_ && $_ !~ /^\s*$/ } @queue;
    return unless @queue;

    if ( my $sub = $state_dispatch{ $self->state } ) {
        return $sub->($self);
    }

    my $highest_priority_delaying    = -999;
    my $highest_priority_nondelaying = -999;
    foreach my $lineno ( 0 .. $#queue ) {
        my ( $cmd, $args ) = split( /\s/, $queue[$lineno], 2 );
        $cmd  = $queue[$lineno] if ( !defined $cmd );
        $cmd  = lc $cmd;
        $args = '' if ( !defined $args );
        my $CMD = Av4::Commands->cmd_get($cmd);
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
        $cmd  = $queue[$lineno] if ( !defined $cmd );
        $cmd  = lc $cmd;
        $args = '' if ( !defined $args );

        # skip if the user is delayed and this command delays
        my $CMD = Av4::Commands->cmd_get($cmd);
        next if ( $self->delay && $CMD->delays );
        if ( $CMD->priority() >= $highest_priority ) {
            my $delay = $CMD->exec( $self->id, $self, $args );
            $Av4::cmd_processed++;
            $self->delay( $self->delay + $delay );
            $self->prompt if ( $cmd !~ /^\s*quit\s*$/ );

            #$self->prompttimer(AnyEvent->timer( after => $self->delay, cb => sub { $self->prompt() })) if $self->delay;
            my $command_dispatched = $queue[$lineno];
            delete $queue[$lineno];

            # weeds out empty and unknown commands
            {
                my @cmds = grep { defined $_ && $_ !~ /^\s*$/ } @queue;
                $self->queue( \@cmds );
            }
            return (
                $command_dispatched,
                $cmd =~ /^\#\$\#mcp/ ? 1 : 0,    # redispatch if MCP command (negotiation)
            );
        }
    }
    my @cmds = grep { defined $_ && $_ !~ /^\s*$/ } @queue;
    $self->queue( \@cmds );
    return;
}

1;
