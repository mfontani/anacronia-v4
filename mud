#!/usr/bin/env perl
use Getopt::Long;
use Pod::Usage;
use lib './lib';
use Av4;

my $port          = 0;
my $tick_commands = 0;
my $fake          = 0;
my $helpfile      = '';
my $show_help     = 0;
my $show_man      = 0;

GetOptions(
  'help!'           => \$show_help,
  'man!'            => \$show_man,
  'port=i'          => \$port,
  'fake!'           => \$fake,
  'tick_commands=i' => \$tick_commands,
  'helpfile=s'      => \$helpfile,
) or pod2usage(2);
pod2usage(1) if $show_help;
pod2usage( -exitstatus => 0, -verbose => 2 ) if $show_man;

my $av4 = Av4->new(
  ( $port          ? ( port          => $port )                : () ),
  ( $fake          ? ( fake          => $fake )                : () ),
  ( $tick_commands ? ( tick_commands => $tick_commands / 100 ) : () ),
  ( $helpfile      ? ( helpfile      => $helpfile )            : () ),
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

=item B<-port> NNN

Sets the port the mud will listen to (defaults to 8081)

=item B<-fake>

If set, the POE sessions are not started.

=item B<-tick_commands> NNMM

Sets how often (in centiseconds) commands are processed for clients (defaults to 100, for every second).
This parameter is actually divided by 100 before being passed to the Av4 constructor.

=item B<-helpfile> filename.are

Sets the filename (help.are from smaug format) which should be parsed in order to
make help pages available to clients. Defaults to help.are in the developer's
home directory.

=back

=head1 DESCRIPTION

B<This program> launches a daemon running on the port specified, which acccepts
connections and replies to the commands the clients give it. A C<help.are> file
is parsed for help pages, and the help pages are made available to the clients
through the C<help> in-game command.

=cut
