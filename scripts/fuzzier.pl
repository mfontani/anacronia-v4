#!/usr/bin/perl -w
use strict;
use lib './inc/lib/perl5', './lib';

BEGIN {
    if ( $^O eq 'darwin' ) {
        require AnyEvent::Impl::IOAsync;    # 'bad symbol for filehandle' given by Event
    }
    else {
        require AnyEvent::Impl::EV;
    }
}
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Time::HiRes qw/tv_interval gettimeofday time/;
use Getopt::Long;
{
    no warnings 'redefine';

    package AE;
    sub time () { goto &Time::HiRes::time }
    sub now ()  { goto &Time::HiRes::time }

    package AnyEvent;
    sub time () { goto &Time::HiRes::time }
    sub now ()  { goto &Time::HiRes::time }
}

warn "\e[0mUsing \e[35mIO::Async\e[0m event loop...\n"
  if exists $INC{'AnyEvent/Impl/IOAsync.pm'};
warn "\e[0mUsing \e[35mEvent\e[0m event loop...\n"
  if exists $INC{'AnyEvent/Impl/Event.pm'};
warn "\e[0mUsing \e[32mEV\e[0m event loop...\n"
  if exists $INC{'AnyEvent/Impl/EV.pm'};
die "\e[0mRefusing to run under \e[31mPerl\e[0m event loop...\n" . "Please install either IO::Async or EV, and load them in ./mud\n"
  if exists $INC{'AnyEvent/Impl/Perl.pm'};

my $nclients   = 80;
my $host       = '127.0.0.1';
my $port       = 8081;
my $mccp       = 0;
my $waitdelay0 = 2;             # how many (delay 0.0) to wait for before sending a new command
my $mintimecmd = 0.5;           # do not send more than one command every X
my $idlecmds   = 0.5;           # send a command if idle more than this

GetOptions(
    'clients=i'    => \$nclients,
    'host=s'       => \$host,
    'port=s'       => \$port,
    'waitdelay0=i' => \$waitdelay0,
    'mintimecmd=s' => \$mintimecmd,
    'idlecmds=s'   => \$idlecmds,
    'mccp'         => \$mccp,
);
warn "Options: --clients $nclients --host $host --port $port --waitdelay0 $waitdelay0 --mintimecmd $mintimecmd --idlecmds $idlecmds "
  . ( $mccp ? '--mccp' : '( did not choose --mccp)' ) . "\r\n";

# Spawn N clients
warn "Spawning $nclients clients...\n";
warn "Will fake MCCP\n" if $mccp;
my $commands = 0;
my $begin    = time;

my $cv = AnyEvent->condvar;

my %clients;
my @cb_connections;
my @cb_idlecommands;

sub handle_client_connection {
    my $clin = shift;
    $cb_connections[$clin] = AnyEvent->timer(
        after => 0.10 * $clin,
        cb    => sub {
            tcp_connect(
                $host, $port,
                sub {
                    my ($fh) = shift;
                    if ( !$fh ) {
                        warn "(client $clin) Cannot connect: $!";
                        delete $clients{$clin};
                        if ( !%clients ) {
                            $cv->send;
                            return;
                        }
                        warn "Redoing for client $clin..\n";
                        handle_client_connection($clin);    # redo
                        return;
                    }

                    my $handle;                             # avoid direct assignment so on_eof has it in scope.
                    $handle = new AnyEvent::Handle
                      fh     => $fh,
                      on_eof => sub {
                        $handle->destroy;                   # destroy handle
                        warn "Client $clin done.\n";
                        delete $clients{$clin};
                        if ( !%clients ) {
                            $cv->send;
                            return;
                        }
                      };
                    $clients{$clin} = $handle;
                    $handle->on_error(
                        sub {
                            my ( $hdl, $fatal, $msg ) = @_;
                            warn "Client $clin - error '$msg' - destroying";
                            $hdl->destroy;
                            delete $clients{$clin};
                            if ( !%clients ) {
                                $cv->send;
                            }
                        }
                    );
                    $handle->push_write( sprintf( "%c%c%c", 255, 253, 86 ) ) if $mccp;    # IAC DO COMPRESS2
                    my $name = random_name();

                    #warn "Client $clin - name is " . $name;
                    $handle->push_write("$name\n");
                    my $received_delay_0 = 0;
                    my $last_command     = time;
                    my $last_delay0      = time;
                    $handle->on_read(
                        sub {
                            my $handle = shift;
                            my $line   = $handle->{rbuf};
                            $handle->{rbuf} = '';

                            #warn "Client $clin got line: $line";
                            return unless ( $line =~ /delay 0.0/ && ( $received_delay_0++ > $waitdelay0 ) );
                            return unless ( time - $last_command > $mintimecmd );
                            $last_delay0 = time;
                            my $cmd = rand_command();

                            #warn "(input) Client $clin -> $cmd\n";
                            $handle->push_write( $cmd . "\r\n" );
                            $last_command     = time;
                            $received_delay_0 = 0;
                            $commands++;
                        }
                    );
                    push @cb_idlecommands, AnyEvent->timer(
                        after    => $idlecmds,
                        interval => $idlecmds,
                        cb       => sub {
                            return unless ( time - $last_command > $mintimecmd * 2 );
                            my $cmd = rand_command();

                            #warn "(idle) Client $clin -> $cmd\n";
                            $handle->push_write( $cmd . "\r\n" );
                            $last_command     = time;
                            $received_delay_0 = 0;
                            $commands++;
                        }
                    );
                },
                sub { 30 },    # timeout in seconds
            );
        }
    );
}

foreach my $clin ( 1 .. $nclients ) {
    handle_client_connection($clin);
}

my @commands = qw/
  areas areas areas
  shout
  say say say say
  help help
  commands
  colors
  help help help
  stats stats stats
  hlist hlist
  look
  n s w e u d ne se nw sw
  n s w e u d ne se nw sw
  @goto/;
my @helps = qw/help anacronia commands shout say colors who online stats shutdown/;

sub rand_command {

    #return (int(rand(2))?"shout power ":"power ") . int(rand(9000)) . "\r\n";
    my $ret = $commands[ rand @commands ];
    if ( $ret eq '@goto' ) {
        return $ret . ' ' . int( 30 + rand(4) );
    }
    if ( $ret eq 'look' ) {
        return $ret;
    }
    if ( $ret eq 'who' ) { # WHO <arg> or just WHO
        return $ret . ' ' . chr(ord('a') + int(rand(20))) if ( rand(1) );
        return $ret;
    }
    $ret .= ' ';
    $ret .= $helps[ rand @helps ];
    return $ret;
}

sub random_name {
    my $name = '';
    for ( 0 .. 9 ) {
        $name .= chr( int( rand(20) ) + ord 'a' );
    }
    return $name;
}

# Run the clients until the last one has shut down.
$cv->recv;

my $seconds = time - $begin;
printf( "Sent %d commands in %d seconds: %2.2f commands/second\n", $commands, $seconds, ( $commands / $seconds ) ) if $seconds;
exit 0;
