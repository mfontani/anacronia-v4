package Av4::Commands::Basic;
require Av4;
require Av4::AreaParse;
require Av4::Room;
require Av4::Commands;
use Av4::Utils qw/get_logger ansify/;
use Av4::Telnet qw/_256col/;

sub cmd_shutdown {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info( "Shutdown initiated by ", $user->id );
    Av4->shutdown($user);
    return [0];
}

sub cmd_shout { goto &cmd_say }

sub cmd_old_shout {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    if ( !$argstr ) {
        return [ 0, "What would you like to shout?\r\n" ];
    }

    #my $log = get_logger();
    #$log->info("$client shouts $argstr");
    my $ansified = ansify("&W$argstr");
    $user->broadcast(
        $client,
        $Av4::Utils::ANSI{'&r'}
          . $user->name
          . " shouts: $ansified\r\n",
        "$Av4::Utils::ANSI{'&r'}You shout: $ansified\r\n",
        1,    # send prompt to others
    );
    return [0];
}

sub cmd_say {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    if ( !$argstr ) {
        return [ 0, "What would you like to say?\r\n" ];
    }
    my $room = $Av4::Room::rooms{ $user->in_room() };
    if ( !$room ) {
        return [ 0, "You are not in a room!\r\n" ];
    }
    my $ansified = ansify("&W$argstr");
    $room->broadcast(
        $user,
        $Av4::Utils::ANSI{'&w'} . $user->name . " says: $ansified\r\n",
        $Av4::Utils::ANSI{'&w'} . "You say: $ansified\r\n",
    );
    return [0];
}

my $_cmd_colors;

sub cmd_colors {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    if ( !defined $_cmd_colors ) {
        my $output = "&RColors:&!\r\n";
        foreach my $lcletter ( split( '', 'xrgybpcw' ) ) {
            foreach my $char ( '&', '^' ) {
                $output .= '    ' if ( $char eq '^' );
                foreach my $letter ( lc $lcletter, uc $lcletter ) {
                    $output .= '   ' if ( uc $letter eq $letter );
                    $output .= "$char$char$letter => $char${letter}XXX&^";
                    my $ansified = ansify("$char$letter&^");
                    $ansified =~ s/\e\[0m//g;
                    $ansified =~ s/\033/\\e/g;
                    $output .= " =  $ansified";
                }
            }
            $output .= "\r\n";
        }
        $_cmd_colors = ansify($output) . _256col();
    }
    return [ 0, $_cmd_colors ];
}

our $wholist;

# No longer used as it was pushing out 117KiB on 800 connections O_O
# Now only used if < 20 players, or if the user gave a pattern in $argstr
sub cmd_long_who {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );

    if ( !$argstr ) {
        if ( $user->name ne 'okram' ) {
            return [ 0, $wholist ] if defined $wholist;
        }
        my $output = '';
        $output .= $Av4::Utils::ANSI{'&g'} . '#' x 35 . ' ONLINE ' . '#' x 35 . $Av4::Utils::ANSI{'&^'} . "\r\n";
        foreach my $plr ( @{ $user->server->clients } ) {
            next if ( !defined $plr );
            my $t = $plr->telopts;
            $output .= sprintf(
                "%-30s %-20s %s %s %s %s %s%s\r\n",
                $Av4::Utils::ANSI{'&r'} . $plr,
                $Av4::Utils::ANSI{'&y'} . $plr->name,
                $t->mxp                      ? $Av4::Utils::ANSI{'&g'} . 'MXP  ' : $Av4::Utils::ANSI{'&R'} . '!MXP ',
                $t->mccp                     ? $Av4::Utils::ANSI{'&g'} . 'MCCP ' : $Av4::Utils::ANSI{'&R'} . '!MCCP',
                $plr->mcp_authentication_key ? $Av4::Utils::ANSI{'&g'} . 'MCP  ' : $Av4::Utils::ANSI{'&R'} . '!MCP ',
                ( $t->naws_w && $t->naws_h )
                ? $Av4::Utils::ANSI{'&g'} . sprintf( 'NAWS %dx%d', $t->naws_w, $t->naws_h )
                : $Av4::Utils::ANSI{'&R'} . '!NAWS',
                $user->name eq 'okram'    # FIXME -- if $user is admin
                ? $Av4::Utils::ANSI{'&p'} . sprintf( '%s:%s', $plr->host, $plr->port )
                : '',
                $Av4::Utils::ANSI{'&^'},
            );
        }
        $output .= $Av4::Utils::ANSI{'&g'} . sprintf( "%d users total.", scalar @{ $user->server->clients } ) . $Av4::Utils::ANSI{'&^'};
        $wholist = $output if $user->name ne 'okram';
        return [ 0, $output ];
    }

    my $output = '';
    $output .= $Av4::Utils::ANSI{'&g'} . '#' x 35 . ' ONLINE ' . '#' x 35 . $Av4::Utils::ANSI{'&^'} . "\r\n";
    $output .= $Av4::Utils::ANSI{'&W'} . '----- Players matching: ' . $Av4::Utils::ANSI{'&Y'} . $argstr . "\r\n";

    # List players whose name matches the $argstr given
    my $n_shown = 0;
    foreach my $plr ( @{ $user->server->clients } ) {
        next if ( !defined $plr || $plr->name !~ /^\Q$argstr\E/ );
        $n_shown++;
        my $t = $plr->telopts;
        $output .= sprintf(
            "%-30s %-20s %s %s %s %s %s%s\r\n",
            $Av4::Utils::ANSI{'&r'} . $plr,
            $Av4::Utils::ANSI{'&y'} . $plr->name,
            $t->mxp                      ? $Av4::Utils::ANSI{'&g'} . 'MXP  ' : $Av4::Utils::ANSI{'&R'} . '!MXP ',
            $t->mccp                     ? $Av4::Utils::ANSI{'&g'} . 'MCCP ' : $Av4::Utils::ANSI{'&R'} . '!MCCP',
            $plr->mcp_authentication_key ? $Av4::Utils::ANSI{'&g'} . 'MCP  ' : $Av4::Utils::ANSI{'&R'} . '!MCP ',
            ( $t->naws_w && $t->naws_h )
            ? $Av4::Utils::ANSI{'&g'} . sprintf( 'NAWS %dx%d', $t->naws_w, $t->naws_h )
            : $Av4::Utils::ANSI{'&R'} . '!NAWS',
            $user->name eq 'okram'    # FIXME -- if $user is admin
            ? $Av4::Utils::ANSI{'&p'} . sprintf( '%s:%s', $plr->host, $plr->port )
            : '',
            $Av4::Utils::ANSI{'&^'},
        );
    }

    $output .= sprintf(
        "%s%d %susers matched out of %s%d%s users total.%s",
        $n_shown ? $Av4::Utils::ANSI{'&g'} : $Av4::Utils::ANSI{'&r'},
        $n_shown, $Av4::Utils::ANSI{'&g'}, $Av4::Utils::ANSI{'&Y'}, scalar @{ $user->server->clients },
        $Av4::Utils::ANSI{'&g'}, $Av4::Utils::ANSI{'&^'},
    );
    return [ 0, $output ];
}

sub cmd_who {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );

    # We can manage the "long" who if there are a few players or if the user asked for
    # players matching a pattern.
    goto \&cmd_long_who if ( scalar @{ $user->server->clients } < 20 || length $argstr );

    # Too many players to do a long who
    if ( !defined $wholist ) {
        my $output = '';
        $output .= $Av4::Utils::ANSI{'&g'} . '#' x 15 . ' ONLINE ' . '#' x 15 . $Av4::Utils::ANSI{'&^'} . "\r\n";
        $output .= $Av4::Utils::ANSI{'&r'} . "Too many players online to show them all.\r\n";
        $output .= $Av4::Utils::ANSI{'&W'} . "Use the command: ";
        $output .= "'$Av4::Utils::ANSI{'&Y'}WHO LETTER$Av4::Utils::ANSI{'&W'}' ";
        $output .= "to see info for players whose name begins with that letter.\r\n";
        $output .= $Av4::Utils::ANSI{'&g'} . sprintf( "%d users total.", scalar @{ $user->server->clients } ) . $Av4::Utils::ANSI{'&^'};
        $wholist = $output;
    }
    return [ 0, $wholist ] if defined $wholist;

}

sub cmd_commands {
    my ( $client, $user, $argstr ) = @_;
    return [
        0,
        "$Av4::Utils::ANSI{'&R'}Commands in your queue:\r\n"
          . (
              $user->queue
            ? $user->dumpqueue(1)
            : "$Av4::Utils::ANSI{'&W'}No commands\r\n"
          )
    ];
}

sub cmd_debug {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    $user->print( "You are session #", $user->id, "\r\n" );
    $user->print( "You are user #",    $user,     "\r\n" );
    return [0];
}

sub cmd_help {
    my ( $client, $user, $argstr ) = @_;
    $argstr = 'help' if ( $argstr =~ /^\s*$/ );
    my $helppage = Av4::AreaParse::areahelp( $user->server->helps, $argstr );
    if ( defined $helppage ) {
        return [
            0,
            $Av4::Utils::ANSI{'&Y'}
              . ( '-' x 78 ) . "\n"
              . $Av4::Utils::ANSI{'&B'}
              . 'Level '
              . $Av4::Utils::ANSI{'&W'}
              . $helppage->level
              . $Av4::Utils::ANSI{'&B'}
              . ' Keywords '
              . $Av4::Utils::ANSI{'&O'}
              . $helppage->keywords . "\n"
              . $Av4::Utils::ANSI{'&Y'}
              . ( '-' x 78 )
              . $Av4::Utils::ANSI{'&^'} . "\n"
              . $helppage->data_ansified
              . $Av4::Utils::ANSI{'&Y'}
              . ( '-' x 78 )
              . $Av4::Utils::ANSI{'&^'} . "\n",
        ];
    }
    else {
        my $log = get_logger();
        $log->info("No help page: $argstr");
        return [ 0, "$Av4::Utils::ANSI{'&r'}No such help page: $Av4::Utils::ANSI{'&o'}$argstr\r\n" ];
    }
}

sub cmd_hlist {
    my ( $client, $user, $argstr ) = @_;
    return [
        0,
        "$Av4::Utils::ANSI{'&c'}Available help pages$Av4::Utils::ANSI{'&w'}:\n"
          . join(
            '', map { sprintf("L %-3d %s\n", $_->level, "@{ $_->keywords }" ) }
              grep { $_->keywords->[0] !~ /^_/ }
              sort { $a->keywords->[0] cmp $b->keywords->[0] } @{ $user->server->helps }
          )
          . $Av4::Utils::ANSI{"&c"}
          . scalar @{ $user->server->helps }
          . ' help pages found.'
          . $Av4::Utils::ANSI{'&^'},
        ".\n"
    ];
}

sub cmd_areas {
    my ( $client, $user, $argstr ) = @_;
    return [
        0,
        "$Av4::Utils::ANSI{'&c'}Areas$Av4::Utils::ANSI{'&w'}:\n" . join(
            '',
            map {
                sprintf(
                    "%4d %-25s %-30s (%d rooms: %s)\n",
                    $_->id, $_->filename, $_->name,
                    scalar @{ $_->rooms },
                    join( ', ', map { $_->vnum } @{ $_->rooms } )
                  )
              }
              sort { $a->id <=> $b->id } @{ $user->server->areas }
          )
          . $Av4::Utils::ANSI{"&c"}
          . scalar @{ $user->server->areas }
          . ' areas found.'
          . $Av4::Utils::ANSI{'&^'},
        ".\n"
    ];
}

sub cmd_stats {
    my ( $client, $user, $argstr ) = @_;
    my $output = '';

    $output .= "$Av4::Utils::ANSI{'&g'}Statistics for user " . $user->id . ":\r\n";

    if ( ref $user eq 'Av4::Entity::Mobile' ) {
        $output .= "You are a mobile. shoo.\r\n";
    }

    if ( ref $user eq 'Av4::Entity::Player' ) {
        my $t = $user->telopts;
        $output .= "  $Av4::Utils::ANSI{'&w'}Your terminal is: " . $t->terminaltype . "\r\n";
        if ( $t->naws_w && $t->naws_h ) {
            $output .= '  Your terminal is showing ' . $t->naws_w . " columns and " . $t->naws_h . " lines.\r\n";
        }
        else {
            $output .= "  Your terminal does $Av4::Utils::ANSI{'&r'}not$Av4::Utils::ANSI{'&w'} support sending NAWS on window resize\r\n";
        }
        if ( $t->mxp ) {
            $output .= "  $Av4::Utils::ANSI{'&g'}You are using MXP\r\n";
        }
        else {
            $output .= "  $Av4::Utils::ANSI{'&r'}You are NOT using MXP\r\n";
        }
        if ( $t->mccp ) {
            $output .= "  $Av4::Utils::ANSI{'&g'}You are using MCCP\r\n";
        }
        else {
            $output .= "  $Av4::Utils::ANSI{'&r'}You are NOT using MCCP\r\n";
        }
        if ( !$user->mcp_authentication_key ) {
            $output .= "  $Av4::Utils::ANSI{'&r'}You are NOT using MCP\r\n";
        }
        else {
            $output .= "  $Av4::Utils::ANSI{'&g'}You are using MCP:\r\n";
            foreach my $package ( keys %{ $user->mcp_packages_supported } ) {
                next if ( !defined $user->mcp_packages_supported->{$package} );
                $output .= sprintf(
                    "    $Av4::Utils::ANSI{'&w'}v.%s - %s %s\r\n",
                    $user->mcp_packages_supported->{$package}->[0],
                    $user->mcp_packages_supported->{$package}->[1], $package,
                );
            }
        }
    }

    $output .= "$Av4::Utils::ANSI{'&g'}Statistics for the server:\r\n";
    $output .=
        "  $Av4::Utils::ANSI{'&w'}CHARS sent by the mud so far (total): $Av4::mud_chars_sent\r\n"
      . "    sent to non-MCCP sessions (total) : $Av4::mud_chars_sent_nonmccp\r\n"
      . "    sent to MCCP sessions (total)     : $Av4::mud_chars_sent_mccp\r\n"
      . "    sent to MCCP sessions (% of total): "
      . sprintf(
        "%2.2f\r\n",
        $Av4::mud_data_sent ? ( ( $Av4::mud_chars_sent_mccp * 100 / $Av4::mud_chars_sent ) )
        : 0.0
      )
      . "  DATA  sent by the mud so far (total): $Av4::mud_data_sent\r\n"
      . "    sent to non-MCCP sessions (total) : $Av4::mud_data_sent_nonmccp\r\n"
      . "    sent to MCCP sessions (total)     : $Av4::mud_data_sent_mccp\r\n"
      . "    sent to MCCP sessions (% of total): "
      . sprintf(
        "%2.2f\r\n", $Av4::mud_data_sent ? ( ( $Av4::mud_data_sent_mccp * 100 / $Av4::mud_data_sent ) )
        : 0.0
      )
      . "  MCCP Compression (% compression)    : "
      . sprintf(
        "%2.2f\r\n", $Av4::mud_chars_sent_mccp ? ( 100 - ( $Av4::mud_data_sent_mccp * 100 / $Av4::mud_chars_sent_mccp ) )
        : 0.0
      ) . "  MCCP sent chars vs data: $Av4::mud_chars_sent_mccp chars resulting in $Av4::mud_data_sent_mccp data sent\r\n";

    if ( ref $user eq 'Av4::Entity::Player' && $user->telopts->mccp ) {
        $output .= "$Av4::Utils::ANSI{'&g'}Thanks for using MCCP!\r\n";
    }

    return [ 0, $output ];
}

sub cmd_quit {
    my ( $client, $user, $argstr ) = @_;

    # send quit text
    $user->print("\r\n\r\nBye bye!!\r\n\r\n");

    #$user->id->destroy;
    #$user->id->push_shutdown();
    $user->id->push_shutdown();
    return [0];
}

sub cmd_look {
    my ( $client, $user, $argstr ) = @_;
    my $room = $Av4::Room::rooms{ $user->in_room() };
    return [ 0, "But.. you are nowhere!\r\n" ] unless $room;
    if ($argstr) {
        return [ 0, $user->desc ] if lc $argstr eq 'me';
        for my $ent ( @{ $room->entities } ) {
            if ( $argstr ~~ @{ $ent->keywords } ) {
                return [ 0, sprintf( "You look at %s:\r\n%s\r\n", $ent->name, $ent->desc ) ];
            }
        }
        for my $ent ( @{ $room->exits } ) {
            if ( $argstr ~~ @{ $ent->{keywords} } ) {
                return [
                    0,
                    sprintf(
                        "You look at the exit towards %s (%s):\r\n%s\r\n",
                        Av4::Room::dir_name( $ent->{door} ),
                        "@{$ent->{keywords}}", $ent->{desc}
                    )
                ];
            }
            if ( lc $argstr eq lc Av4::Room::dir_name( $ent->{door} ) ) {
                $user->print( sprintf( "You look at the exit towards %s:\r\n", Av4::Room::dir_name( $ent->{door} ) ) );

                # tmp put user in other room
                my $cur_room = $user->in_room;
                $user->in_room( $ent->{to_vnum} );
                if ( my $cmd_look = Av4::Commands->cmd_get('look') ) {
                    $cmd_look->exec( $user->id, $user, '' );
                }
                $user->in_room($cur_room);
                return [0];
            }
        }
        return [ 0, 'No such thing here :(' ];
    }
    return [
        0,
        $room->vnum . ' - '
          . $Av4::Utils::ANSI{'&c'}
          . $room->name
          . $Av4::Utils::ANSI{'&^'} . "\r\n"
          . $room->desc_ansi
          . $Av4::Utils::ANSI{'&^'}
          . (
            @{ $room->exits }
            ? "\r\n" . $Av4::Utils::ANSI{'&W'} . 'Exits: ' . join(
                ' ',
                map {
                    sprintf( "%s%s:%s%s%s",
                        defined $_->{locks} ? '[' : '',
                        Av4::Room::dir_name( $_->{door} ),
                        defined $_->{to_vnum} ? $_->{to_vnum} : '??',
                        defined $_->{locks}   ? ']'           : '',
                        defined $_->{keywords} && @{ $_->{keywords} } ? "(@{$_->{keywords}})" : '',
                      )
                  } @{ $room->exits }
              )
            : ''
          )
          .    # . "\r\nData from file:\r\n" . $room->{data}
          (
            ( @{ $room->entities } > 1 )
            ? (
                    "\r\n" 
                  . join( "\r\n",
                    map { sprintf( '%s - %s', $_->name, $_->short ) }
                    grep { defined }
                    grep { $_ ne $user } @{ $room->entities } )
                  . $Av4::Util::ANSI{'&^'} . "\r\n"
              )
            : ''
          )
    ];
}

sub cmd_goto {
    my ( $client, $user, $argstr ) = @_;
    return [ 0, '@goto: need a VNUM to go to..' . "\r\n" ]
      unless $argstr && $argstr =~ /^\d+$/;
    return [ 0, '@goto: no such VNUM' . "\r\n" ]
      unless exists $Av4::Room::rooms{$argstr};
    $user->move_to_room(
        $argstr,
        "\nWOOSH! You disappear into thin air..\r\n",
        sprintf( "%s disappears into thin air...\r\n", $user->name ),
        "\nWOOSH! You appear in room #$argstr\r\n\r\n",
        sprintf( "%s appears from thin air...\r\n", $user->name ),
    );
    if ( my $cmd_look = Av4::Commands->cmd_get('look') ) {
        $cmd_look->exec( $user->id, $user, '' );
    }
    return [0];
}

sub cmd_mpall {
    my ( $client, $user, $argstr ) = @_;
    return [ 0, '@mpapp: need a COMMAND to force all to do..' . "\r\n" ]
      unless $argstr && length $argstr;
    my $room = $Av4::Room::rooms{ $user->in_room };
    for my $ent ( @{ $room->entities } ) {
        next if $ent == $user;
        unshift @{ $ent->queue }, $argstr;
    }
    return [ 0, "Done." ];
}

sub cmd_move {
    my ( $client, $user, $argstr, $dir ) = @_;
    return [ 0, "Where are you!?" ]   unless $user->in_room;
    return [ 0, "You are nowhere!?" ] unless exists $Av4::Room::rooms{ $user->in_room };
    return [ 0, "No direction :(" ]   unless $dir && length $dir;
    return [ 0, "What direction?!" ]  unless exists $Av4::Room::dir_number{$dir};
    my $dir_number = $Av4::Room::dir_number{$dir};
    my $room       = $Av4::Room::rooms{ $user->in_room };
    for my $exit ( @{ $room->exits } ) {
        next unless $exit->{door} eq $dir_number;
        my $new_room = $Av4::Room::rooms{ $exit->{to_vnum} };
        if ( !$new_room ) {
            warn "AIEE new room vnum $exit->{to_vnum} not found";
            next;
        }
        $user->move_to_room(
            $exit->{to_vnum},
            "You go $dir..\r\n",
            sprintf( "%s leaves towards %s...\r\n", $user->name, $dir ),
            '', sprintf( "%s enters the room from %s...\r\n", $user->name, Av4::Room::rev_dir_name($dir_number) ),
        );
        return cmd_look( $client, $user, '' );
    }
    return [ 0, "You bump into something." ];
}

1;
