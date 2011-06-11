#!perl5/perlbrew/perls/perl-5.14.0/bin/perl
use strict;
use warnings;
use v5.14.0;
use Getopt::Long;
use Pod::Usage;
use lib './inc/lib/perl5/', './lib';

# Ensure the wanted AnyEvent implementation is loaded on OSX
BEGIN {
    if ( $^O eq 'darwin' ) {
        require AnyEvent::Impl::Event;
    }
    else {
        require AnyEvent::Impl::EV;
    }
}

# Ensure the person has ran Build.PL, Build and built the XS stuff
BEGIN {
    die "

    Please launch:
        perl Build.PL
        ./Build

    before attempting to launch ./mud again.

    \n" if ( !-f 'auto/Av4/Ansi/Ansi.bs' );

}
use Av4;

# Show the implementation being used, or die if it tries to use the pure-Perl version
{
    warn "\e[0mUsing \e[35mIO::Async\e[0m event loop...\n"
      if exists $INC{'AnyEvent/Impl/IOAsync.pm'};
    warn "\e[0mUsing \e[35mEvent\e[0m event loop...\n"
      if exists $INC{'AnyEvent/Impl/Event.pm'};
    warn "\e[0mUsing \e[32mEV\e[0m event loop...\n"
      if exists $INC{'AnyEvent/Impl/EV.pm'};
    die "\e[0mRefusing to run under \e[31mPerl\e[0m event loop...\nPlease install either Event, IO::Async or EV, and load them in ./mud\n"
      if exists $INC{'AnyEvent/Impl/Perl.pm'};
}

my $address       = undef;
my $port          = 0;
my $tick_commands = 0;
my $tick_mobiles  = 0;
my $tick_flush    = 0;
my $fake          = 0;
my $areadir       = '';
my $show_help     = 0;
my $show_man      = 0;

GetOptions(
    'help!'           => \$show_help,
    'man!'            => \$show_man,
    'address=s'       => \$address,
    'port=s'          => \$port,
    'fake!'           => \$fake,
    'tick_commands=s' => \$tick_commands,
    'tick_mobiles=s'  => \$tick_mobiles,
    'tick_flush=s'    => \$tick_flush,
    'areadir=s'       => \$areadir,
) or pod2usage(2);
pod2usage(1) if $show_help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $show_man;

die "Don't even try running this on a port <= 1024!\n" if $port && ($address && $address ne 'unix/') && $port <= 1024;

my $av4 = Av4->new(
    ( $address       ? ( listen_address => $address )       : () ),
    ( $port          ? ( listen_port    => $port )          : () ),
    ( $fake          ? ( fake           => $fake )          : () ),
    ( $tick_commands ? ( tick_commands  => $tick_commands ) : () ),
    ( $tick_mobiles  ? ( tick_mobiles   => $tick_mobiles )  : () ),
    ( $tick_flush    ? ( tick_flush     => $tick_flush )    : () ),
    ( $areadir       ? ( areadir        => $areadir )       : () ),
);
$av4->run;

__END__

=head1 NAME

mud - Start the Anacronia V4 MUD

=head1 SYNOPSIS

./mud [options]

=head1 OPTIONS

=over 8

=item B<-help>

Prints a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-address> IP or C<unix/>

Sets the address the mud will listen to (defaults to undef, for all interfaces).
In order to bind to a UNIX socket, use the value C<unix/> here.

=item B<-port> NNN or /path/to/unix/socket

Sets the port the mud will listen to (defaults to 8081).
In order to bind to a UNIX socket, use the path to the socket here.
Do B<NOT> specify a value E<lt> 1024 here, thanks.

=item B<-fake>

If set, the sessions are not started.

=item B<-tick_commands> NNMM

Sets how often commands are processed for clients (defaults to whatever is in Av4).

=item B<-tick_mobiles> NNMM

Sets how often mobiles perform random actions (defaults to whatever is in Av4).

=item B<-tick_flush> NNMM

Sets how often clients' buffers are flushed (defaults to whatever is in Av4).

=item B<-areadir> areas/

Sets the directory which contains area files (in JSON format) which should be
used to load areas from. Defaults to C<areas/>.

=back

=head1 DESCRIPTION

B<This program> launches a daemon running on the port specified, which acccepts
connections and replies to the commands the clients give it. The C<areas/>
directory (or the one referenced with the C<-areadir> option) is scanned for
help and area files, and the help pages contained are made available to the
clients through the C<help> and C<hlist> in-game commands.  Rooms and mobiles
are also parsed and made available, as well as some types of resets.

=cut
