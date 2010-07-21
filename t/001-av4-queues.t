#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok( 'Av4' );
    use_ok( 'Av4::User' );
}

can_ok ('Av4', qw/client_read/);
can_ok ('Av4::User', qw/dispatch_command/);

my $srv;
eval {
    $srv = Av4::Server->new(
        kernel => '',
    );
};
ok(!$@, "creating Av4::Server OK") or diag("Cannot create Av4::Server: $@");

my $user;
eval {
    $user = Av4::User->new(
        server => $srv,
        id => 123,
    );
    $user->state(1);
};
ok(!$@, "creating Av4::User OK") or do {
    die("Cannot create Av4::User via given Av4::Server: $@");
};
ok(!@{$user->queue},"User has empty queue when created");

$srv->clients([$user]);
ok(1==@{$srv->clients},"Server has one client connected");

{
    my $str = $user->dumpqueue();
    ok($str =~ /^Queue for user Av4::User=HASH\(0x[0-9a-f]+\):\n$/gm, "Expected message for empty queue")
        or diag("Queue message doesn't match:\n~$str~");
}

{
    $user->queue(['unknown_command']);
    my $str = $user->dumpqueue();
    my @lines = split(/\n/,$str);
    ok(2==@lines,"Got 2 lines from queue");
    ok($lines[0] =~ /^Queue for user Av4::User=HASH\(0x[0-9a-f]+\):$/, "Expected first line")
        or diag("Line 0 not what expected: ~$lines[0]~");
    ok($lines[1] =~ /^#0  D n\/a PRI n\/a \[UNKNOWN\] unknown_command$/, "Expected second line")
        or diag("Line 1 not what expected: ~$lines[1]~");
}

sub dumpqueue_test_n_commands {
    my ($cmds,$expe) = @_;
    $user->queue([@$cmds]);
    my $str = $user->dumpqueue();
    my @lines = split(/\n/,$str);
    ok((@$expe+1)==@lines,"Got " . (1+scalar @$cmds) . " lines from queue");
    ok($lines[0] =~ /^Queue for user Av4::User=HASH\(0x[0-9a-f]+\):$/, "Expected first line")
        or diag("Line 0 not what expected: ~$lines[0]~");
    for (0..$#$expe) {
        my $n = $_+1;
        my $pri = $expe->[$_]->{priority};
        my $del = $expe->[$_]->{delay};
        my $kno = $expe->[$_]->{known};
        my $nam = $expe->[$_]->{name};
        ok($lines[$n] =~ /^#\Q$_\E  D \Q$del\E\s* PRI \Q$pri\E\s* \[\Q$kno\E\] \Q$nam\E$/, "Expected line $n with command $nam")
            or diag("Line $n not what expected: ~$lines[$n]~ vs expected n $n and cmd $nam");
    }
}
dumpqueue_test_n_commands(
    [qw/unknown1 unknown2/],
    [
        { priority => 'n/a', delay => 'n/a', known => 'UNKNOWN', name => 'unknown1' },
        { priority => 'n/a', delay => 'n/a', known => 'UNKNOWN', name => 'unknown2' },
    ]
);
dumpqueue_test_n_commands(
    [qw/unknown1 help unknown2/],
    [
        { priority => 'n/a', delay => 'n/a', known => 'UNKNOWN', name => 'unknown1' },
        { priority => '100', delay => '1',   known => 'KNOWN',   name => 'help' },
        { priority => 'n/a', delay => 'n/a', known => 'UNKNOWN', name => 'unknown2' },
    ]
);
dumpqueue_test_n_commands(
    ['unknown1','help me','unknown2'],
    [
        { priority => 'n/a', delay => 'n/a', known => 'UNKNOWN', name => 'unknown1' },
        { priority => '100', delay => '1',   known => 'KNOWN',   name => 'help me' },
        { priority => 'n/a', delay => 'n/a', known => 'UNKNOWN', name => 'unknown2' },
    ]
);

sub dispatch_test_n_commands {
    my ($cmds,@expe) = @_;
    diag("Testing queue: @$cmds");
    $user->queue([@$cmds]);
    my $run = 0;
    for my $expe (@expe) {
        diag("  Testing dispatch_command() run $run");
        $user->delay(0);
        my ($cmd_dispatched,$mcp_command) = $user->dispatch_command();
        my $e_cmd_dispatched = shift @$expe;
        my $e_mcp_command    = shift @$expe;
        is( $cmd_dispatched, $e_cmd_dispatched, '->dispatch_command returned expected cmd_dispatched' );
        is( $mcp_command,    $e_mcp_command,    '->dispatch_command returned expected mcp_command' );
        my $str = $user->dumpqueue();
        my @lines = split(/\n/,$str);
        ok((@$expe+1)==@lines,"Got " . (scalar @$expe+1) . " lines from queue") or diag("Got " . @lines . " from the queue instead of " . (@$expe+1) . ":\n$str\n");
        ok($lines[0] =~ /^Queue for user Av4::User=HASH\(0x[0-9a-f]+\):$/, "Expected first line")
            or diag("Line 0 not what expected: ~$lines[0]~");
        for (0..$#$expe) {
            ok(defined $expe->[$_], 'expected is defined');
            my $n = $_+1;
            my $pri = $expe->[$_]->{priority};
            my $del = $expe->[$_]->{delay};
            my $kno = $expe->[$_]->{known};
            my $nam = $expe->[$_]->{name};
            ok($lines[$n] =~ /^#\Q$_\E  D \Q$del\E\s* PRI \Q$pri\E\s* \[\Q$kno\E\] \Q$nam\E$/, "Expected line $n with command $nam")
                or diag("Line $n not what expected: ~$lines[$n]~ vs expected n $n and cmd $nam");
        }
        $run++;
    }
}

dispatch_test_n_commands(
    ['unknown1','help me','unknown2'],
    [ 'help me', 0, ]
);
dispatch_test_n_commands(
    ['unknown1','help me','help you','unknown2'],
    [
        'help me', 0,
        { priority => '100', delay => '1',   known => 'KNOWN',   name => 'help you' },
    ],
    [ 'help you', 0, ],
    [ undef, undef, ],
);
dispatch_test_n_commands(
    ['unknown1','help me','help you','unknown2','@editname test'],
    [
        '@editname test', 0,
        { priority => '100', delay => '1',   known => 'KNOWN',   name => 'help me' },
        { priority => '100', delay => '1',   known => 'KNOWN',   name => 'help you' },
    ],
);

done_testing();
