#!/usr/bin/env perl
use strict;
use warnings;
use Gearman::XS qw(:constants);
use Gearman::XS::Worker;
use 5.010_000;
use FindBin;
use lib "$FindBin::Bin/../lib", "$FindBin::Bin/../../WEBMIRE/WOTC-Compendium/lib";

use WOTC::Compendium::FastDB;
use JSON::XS;

my $worker = new Gearman::XS::Worker;
my $ret = $worker->add_server( '127.0.0.1', 4730 );
die 'error: ', $worker->error() unless $ret == GEARMAN_SUCCESS;

$ret = $worker->add_function( 'fetch_power', 0, \&fetch_power, 0 );
die 'error: ', $worker->error() unless $ret == GEARMAN_SUCCESS;

my $db = WOTC::Compendium::FastDB->new();
say "Awaiting connections...";
while (1) {
    my $ret = $worker->work();
    if ( $ret != GEARMAN_SUCCESS ) {
        warn $worker->error();
        sleep 1;
    }
}

sub fetch_power {
    my ( $job, $opts ) = @_;
    my $workload = decode_json( $job->workload );
    if ( ref $workload ne 'HASH' ) {
        warn "Workload received doesn't look like a hash!\n";
        return 'NOT A HASH';
    }
    my @r = $db->connection->resultset('Power')->search( { id => $workload->{id} } );
    return 'NOT FOUND' unless @r;
    return $r[0]->html;
}

