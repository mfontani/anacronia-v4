#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Differences;
use utf8;

BEGIN {
    use_ok( 'Av4::TelnetOptions' );
}

use Av4::Telnet qw/
  %TELOPTS %TELOPTIONS
  TELOPT_FIRST
  TELOPT_WILL TELOPT_WONT
  TELOPT_DO TELOPT_DONT
  TELOPT_IAC TELOPT_SB TELOPT_SE
  TELOPT_COMPRESS2 TELOPT_MSP TELOPT_MXP
  TELOPT_TTYPE TELOPT_NAWS
/;

sub readable
{
    my @bytes;
    for my $text (@_)
    {
        my @b = map { ord } split('', $text );
        push @bytes, @b;
    }
    my $output = '';
    for my $byte ( @bytes )
    {
        if    (exists( $TELOPTS{$byte} )) { $output .= $TELOPTS{$byte} }
        elsif (exists( $TELOPTIONS{$byte} )) { $output .= $TELOPTIONS{$byte} }
        else { $output .= sprintf("%x",$byte); }
        $output .= ', ';
    }
    return $output;
}

{
    package Av4::User::PushWriteable::Mocked;
    our $self;
    our $out_buf = '';
    sub new { $self = bless {}, __PACKAGE__ unless $self; $self }
    sub push_write { shift;
        $out_buf .= $_ for @_;
        Test::More::diag("push_write(" . main::readable(@_) . ")");
    }
    sub _out_buf { my $old = $out_buf; $out_buf = ''; $old }

    package Av4::User::Mocked;
    our $out_buf = '';
    sub print {
        shift;
        $out_buf .= $_ for @_;
        Test::More::diag("Printed: " . main::readable(@_));
    }
    sub id {
        Av4::User::PushWriteable::Mocked->new;
    }
    sub _out_buf { my $old = $out_buf; $out_buf = ''; $old }
    sub new { bless {}, $_[0] }
}

can_ok ('Av4::TelnetOptions', qw/analyze/);
can_ok ('Av4::User::Mocked', $_ ) for qw/new print/;

my $t = Av4::TelnetOptions->new( user => Av4::User::Mocked->new );
ok($t,'Av4::TelnetOptions created');

is($t->naws_w,0,'default no naws w');
is($t->naws_h,0,'default no naws h');
is($t->state_got_naws,0,'default no state_got_naws');
eq_or_diff($t->state_naws,[],'default nothing on state_naws');
eq_or_diff(
    $t->analyze(
        sprintf("%c%c%c",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_WILL,
            Av4::Telnet::TELOPT_NAWS,
        ),
    ),
    '',
    'simple naws WILL is filtered'
);
is($t->naws_w,0,'default no naws w');
is($t->naws_h,0,'default no naws h');
is($t->state_got_naws,0,'default no state_got_naws');
eq_or_diff($t->state_naws,[],'default nothing on state_naws');

eq_or_diff(
    $t->analyze(
        sprintf("%c%c%c%c%c%c%c%c%c",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_SB,
            Av4::Telnet::TELOPT_NAWS,
            0, 100, 0, 33,
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_SE,
        ),
    ),
    '',
    'simple naws DATA is filtered'
);
is($t->naws_w,100,'got naws width 100');
is($t->naws_h,33,'got naws height 33');
is($t->state_got_naws,0,'got no naws as naws already done');
eq_or_diff($t->state_naws,[0,100,0,33],'data on naws');

done_testing();
