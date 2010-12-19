package Av4::Commands::Basic;
require Av4;
require Av4::HelpParse;
use Av4::Utils qw/get_logger ansify/;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(cmd_shout cmd_commands cmd_debug cmd_help cmd_quit);

sub cmd_shutdown {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info( "Shutdown initiated by ", $user->id );
    Av4->shutdown($user);
}

sub cmd_shout {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    my $log = get_logger();
    if ( !$argstr ) {
        $user->print("What would you like to shout?\r\n");
        return 0;
    }
    #$log->info("$client shouts $argstr");
    $user->broadcast(
        $client,
        "&r$client shouts: &W$argstr\n\r",
        "&rYou shout: &W$argstr\n\r",
        1,    # send prompt to others
    );
}

sub cmd_colors {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    my $log    = get_logger();
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
    $user->print( ansify($output) );
}

sub cmd_who {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    my $log = get_logger();
    $user->print( ansify( "&g" . '#' x 32 . ' ONLINE ' . '#' x 32 . "\r\n" ) );
    foreach my $plr ( @{ $user->server->clients } ) {
        next if ( !defined $plr );
        $user->print(
            ansify(
                sprintf(
                    "%-30s %-20s %-5s %-5s %-5s\r\n",
                    $plr,
                    $plr->name,
                    $plr->telopts->mccp          ? '&GMCCP' : '!MCCP',
                    $plr->mcp_authentication_key ? '&GMCP'  : '!MCP',
                    $plr->telopts->naws_w && $plr->telopts->naws_h ? '&GNAWS' : '!NAWS',
                )
            )
        );
    }
    $user->print( ansify( sprintf "&g%d users total.\r\n", scalar @{ $user->server->clients } ) );
}

sub cmd_commands {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $user->print( ansify("&RCommands in your queue:\r\n") );
    if ( !$user->queue ) {
        $user->print( ansify("&WNo commands\r\n") );
    } else {
        $user->print( $user->dumpqueue(1) );

        #for ( 0 .. $#{ $user->queue } ) {
        #    $user->print( ansify( sprintf( "&W%02d &C%s\r\n", $_, $user->queue->[$_] ) ) );
        #}
    }
}

sub cmd_debug {
    my ( $client, $user, $argstr ) = @_;
    $argstr = '' if ( $argstr =~ /^\s*$/ );
    my $log = get_logger();
    $user->print( "You are session #", $user->id, "\r\n" );
    $user->print( "You are user #",    $user,     "\r\n" );
}

sub cmd_help {
    my ( $client, $user, $argstr ) = @_;
    $argstr = 'help' if ( $argstr =~ /^\s*$/ );
    my $log = get_logger();
    my $helppage = Av4::HelpParse::areahelp( $user->server->helps, $argstr );
    if ( defined $helppage ) {
        $user->print( ansify( $helppage->data ), "\n" );
        $log->info("Sent $client help page on $argstr");
    } else {
        $user->print( ansify("&rNo such help page: &o$argstr\r\n") );
        $log->info("No help page: $argstr");
        return 0;
    }
}

sub cmd_stats {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();

    $user->print( ansify( "&gStatistics for user " . $user->id . ":\r\n" ) );
    $user->print( ' Your terminal is: ', $user->telopts->terminaltype, "\r\n", );
    if ( $user->telopts->naws_w && $user->telopts->naws_h ) {
        $user->print(
            ' Your terminal is showing ',
            $user->telopts->naws_w, " columns and ",
            $user->telopts->naws_h, " lines.", "\r\n"
        );
    } else {
        $user->print(" Your terminal does not support sending NAWS on window resize\r\n");
    }
    if ( $user->telopts->mccp ) {
        $user->print( ' ', ansify("&gYou are using MCCP\r\n") );
    } else {
        $user->print( ' ', ansify("&rYou are NOT using MCCP\r\n") );
    }
    if ( !$user->mcp_authentication_key ) {
        $user->print( ' You are ', ansify("&rNOT"), " using MCP\r\n" );
    } else {
        $user->print(" You are using MCP:\r\n");
        foreach my $package ( keys %{ $user->mcp_packages_supported } ) {
            next if ( !defined $user->mcp_packages_supported->{$package} );
            $user->print(
                sprintf(
                    "   v.%s - %s %s\r\n",
                    $user->mcp_packages_supported->{$package}->[0],
                    $user->mcp_packages_supported->{$package}->[1],
                    $package,
                )
            );
        }
    }

    $user->print( ansify("&gStatistics for the server:\r\n") );
    $user->print(
        " CHARS sent by the mud so far (total): ",
        $Av4::mud_chars_sent,
        "\r\n",
        "   sent to non-MCCP sessions (total) : ",
        $Av4::mud_chars_sent_nonmccp,
        "\r\n",
        "   sent to MCCP sessions (total)     : ",
        $Av4::mud_chars_sent_mccp,
        "\r\n",
        "   sent to MCCP sessions (% of total): ",
        sprintf( "%2.2f",
            $Av4::mud_data_sent
            ? ( ( $Av4::mud_chars_sent_mccp * 100 / $Av4::mud_chars_sent ) )
            : 0.0 ),
        "\r\n",
    );
    $user->print(
        " DATA  sent by the mud so far (total): ",
        $Av4::mud_data_sent,
        "\r\n",
        "   sent to non-MCCP sessions (total) : ",
        $Av4::mud_data_sent_nonmccp,
        "\r\n",
        "   sent to MCCP sessions (total)     : ",
        $Av4::mud_data_sent_mccp,
        "\r\n",
        "   sent to MCCP sessions (% of total): ",
        sprintf( "%2.2f",
            $Av4::mud_data_sent
            ? ( ( $Av4::mud_data_sent_mccp * 100 / $Av4::mud_data_sent ) )
            : 0.0 ),
        "\r\n",
    );
    $user->print(
        ' MCCP Compression (% compression)    : ',
        sprintf( "%2.2f",
            $Av4::mud_chars_sent_mccp
            ? ( 100 - ( $Av4::mud_data_sent_mccp * 100 / $Av4::mud_chars_sent_mccp ) )
            : 0.0 ),
        "\r\n",
        ' MCCP sent chars vs data: ',
        $Av4::mud_chars_sent_mccp,
        ' chars resulting in ',
        $Av4::mud_data_sent_mccp,
        ' data sent',
        "\r\n",
    );

    if ( $user->telopts->mccp ) {
        $user->print( ansify("&rThanks"), " for using MCCP!\r\n", );
    }

}

sub cmd_quit {
    my ( $client, $user, $argstr ) = @_;

    # send quit text
    $user->print("\r\n\r\nBye bye!!\r\n\r\n");
    $user->id->destroy;
}

1;
