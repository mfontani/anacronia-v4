package Av4::Commands::Delegated;
use strict;
use warnings;
require Av4;

sub cmd_power {
    my ( $client, $user, $argstr ) = @_;
    if ( !$argstr || $argstr !~ /^\d+$/ ) {
        return [ 0, "Which power (number)?\r\n" ];
    }
    $Av4::gearman->add_task(
        fetch_power => sprintf( '{"id":%d}', int($argstr) ),
        on_complete => sub {
            my $result = $_[1];
            $user->print("\nHTML:\n$result\n\n");
            $user->print( $user->prompt );
        },
        on_fail => sub {
            $user->print( "\n" . $Av4::Utils::ANSI{'&R'} . "(ERROR FETCHING POWER $argstr)" . $Av4::Utils::ANSI{'&^'} . "\n\n" );
            $user->print( $user->prompt );
        },
    );
    return [ 5, "Scheduled..\r\n" ];
}

1;
