#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok( 'Av4::TelnetOptions' );
}

{
    package Av4::User::Mocked;
    sub print {
        diag("Printed: @_");
        join('',@_);
    }
    sub new { bless {}, $_[0] }
}

can_ok ('Av4::TelnetOptions', qw/analyze/);
can_ok ('Av4::User::Mocked', $_ ) for qw/new print/;

my $t = Av4::TelnetOptions->new( user => Av4::User::Mocked->new );
ok($t,'Av4::TelnetOptions created');

done_testing();
