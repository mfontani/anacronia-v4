#!/usr/bin/perl -w
use strict;
use POE::Kernel { loop => 'POE::XS::Loop::EPoll' };
use POE;
use POE::Component::Client::TCP;
use POE::Filter::Stream;
use Getopt::Long;

my $nclients = 80;
my $host     = '127.0.0.1';
my $port     = 8081;
my $mccp     = 0;

GetOptions(
    'clients=i' => \$nclients,
    'host=s'    => \$host,
    'port=i'    => \$port,
    'mccp'      => \$mccp,
);

# Spawn N clients
warn "Spawning $nclients clients...\n";
warn "Will fake MCCP\n" if $mccp;
my $commands = 0;
my $begin    = time;

foreach my $clin ( 1 .. $nclients ) {
    POE::Component::Client::TCP->new(
        RemoteAddress => $host,
        RemotePort    => $port,
        Filter        => "POE::Filter::Stream",
        Connected     => sub {

            $_[HEAP]->{server}->put(sprintf("%c%c%c",255,253,86)) if $mccp; # IAC DO COMPRESS2
            #print "Client $clin connected to $host:$port ...\n";
            $_[HEAP]->{banner_buffer} = [];
            $_[KERNEL]->delay( send_enter => int rand(3) + 1 );
            $_[HEAP]->{server}->put(random_name() . "\n\n");
        },
        ConnectError => sub {
            print "Client $clin could not connect to $host:$port ...\n";
        },
        ServerInput => sub {
            my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];

            #print "Client $clin got input from $host:$port ...\n";
            push @{ $heap->{banner_buffer} }, $input;
            $kernel->delay( send_stuff    => undef );
            $kernel->delay( input_timeout => 1 );
        },
        InlineStates => {
            send_stuff => sub {

                #print "Client $clin sending stuff on $host:$port ...\n";
                $_[HEAP]->{server}->put("");    # sends enter
                $_[KERNEL]->delay( input_timeout => 5 );
                $_[KERNEL]->delay( send_stuff    => int rand(3) + 1 );
            },
            input_timeout => sub {
                my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

                #print "Client $clin got input timeout from $host:$port ...\n";
                if ( !defined $_[HEAP]->{server} ) {
                    print "client $clin shutting down\n";
                    $kernel->yield("shutdown");
                    return;
                }
                $_[KERNEL]->delay( input_timeout => int rand(4) + 1 );
                $_[HEAP]->{server}->put( rand_command() );
                $commands++;

                #print "Client $clin done\n";
            },
        },
    );
}

my @commands = qw/help shout say help who shout help stats shout help say help azs/;
my @helps    = qw/map help massign bede cod cry1 cry2 cry3 cry10/;

sub rand_command {
    return (int(rand(2))?"shout power ":"power ") . int(rand(9000)) . "\r\n";
    my $cmd = ( rand @commands ) + 2;
    my $ret = $commands[ rand @commands ];
    $ret .= ' ';
    $ret .= $helps[ rand @helps ];
    $ret .= "\r\n";
    return $ret;
}

sub random_name {
    my $name = '';
    for (0..9) {
        $name .= chr (int(rand(20))+ord 'a');
    }
    return $name;
}

# Run the clients until the last one has shut down.

$poe_kernel->run();

my $seconds = time - $begin;
printf("Sent %d commands in %d seconds: %2.2f commands/second\n", $commands, $seconds, ($commands/$seconds));
exit 0;
