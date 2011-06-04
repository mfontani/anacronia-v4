package Av4::Commands::MXP;
use Av4::Utils qw/get_logger ansify/;
require Av4::Commands;
require Av4;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(cmd_mcp_blank);

# for user command: "@mxp"
sub cmd_mxp {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info("Got MXP command: `$argstr`");
    return [
        0,
        "\r\n\e[0z$argstr\r\n" . "\r\n\e[1z$argstr\r\n" . "\r\n\e[2z$argstr\r\n" . "\e[7z"    # reset default locked mode
    ];
}

# Got MXP reply: <VERSION MXP="0.5" CLIENT=MUSHclient VERSION="4.71" REGISTERED=YES>
sub cmd_mxp_option {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $argstr =~ s/\e\[\dz//gi;
    warn("Got MXP reply: $argstr\r\n");
    return [ 0, "Got MXP reply: $argstr\r\n" ];
}
1;
