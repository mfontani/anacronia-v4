package Av4::Commands::Delegated;
require Av4;
require Av4::HelpParse;
use Av4::Utils qw/get_logger ansify/;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(cmd_shout cmd_commands cmd_debug cmd_help cmd_quit);

sub cmd_power {
    my ( $client, $user, $argstr ) = @_;
    if ( !$argstr || $argstr !~ /^\d+$/ ) {
        $user->print("Which power (number)?\r\n");
        return 0;
    }
    $Av4::gearman->add_task(
        fetch_power => sprintf('{"id":%d}',int($argstr)),
        on_complete => sub {
            my $result = $_[1];
            $user->print("\n\n\nHTML:\n$result\n\n");
            $user->print( $user->prompt );
        },
        on_fail => sub {
            $user->print("\n(ERROR FETCHING POWER $argstr)\n\n");
            $user->print( $user->prompt );
        },
    );
    $user->print("Scheduled..\r\n");
    return 5;
}

1;
