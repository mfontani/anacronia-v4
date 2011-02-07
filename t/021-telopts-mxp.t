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
    sub print_raw {
        shift;
        $out_buf .= $_ for @_;
        Test::More::diag("Printed: " . main::readable(@_));
    }
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

is($t->mxp,0,'default no mxp');
eq_or_diff(
    $t->analyze(
        sprintf("%c%c%c",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DO,
            Av4::Telnet::TELOPT_MXP,
        ),
    ),
    '',
    'simple mxp initialization is filtered'
);
is($t->mxp,1,'mxp on after initialization string');
is(
    $t->user->_out_buf,
    sprintf("%c%c%c%c%c\e[7z",
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SB,
        Av4::Telnet::TELOPT_MXP,
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SE,
    ),
    'MUD sent IAC SB MXP IAC SE ESC [7z'
);
is($t->user->id->_out_buf,'','MUD sent nothing after OK MXP');

eq_or_diff(
    $t->analyze(
        sprintf("%c%c%c",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DONT,
            Av4::Telnet::TELOPT_MXP,
        ),
    ),
    '',
    'simple mxp deinitialization is filtered'
);
is($t->mxp,0,'mxp off after deinitialization string');
is($t->user->_out_buf,'','MUD sent nothing after OK MXP');
is($t->user->id->_out_buf,'','MUD sent nothing after OK MXP');

$t = Av4::TelnetOptions->new( user => Av4::User::Mocked->new );
ok($t,'Av4::TelnetOptions created');

is($t->mxp,0,'default no mxp');
eq_or_diff(
    $t->analyze(
        sprintf("te%c%c%cst",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DO,
            Av4::Telnet::TELOPT_MXP,
        ),
    ),
    'test',
    'mxp initialization between two pieces of text is filtered'
);
is($t->mxp,1,'mxp on after initialization string');
is(
    $t->user->_out_buf,
    sprintf("%c%c%c%c%c\e[7z",
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SB,
        Av4::Telnet::TELOPT_MXP,
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SE,
    ),
    'MUD sent IAC SB MXP IAC SE ESC [7z'
);
is($t->user->id->_out_buf,'','MUD sent nothing after OK MXP');

eq_or_diff(
    $t->analyze(
        sprintf("te%c%c%cst",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DONT,
            Av4::Telnet::TELOPT_MXP,
        ),
    ),
    'test',
    'mxp deinitialization between two strings is filtered'
);
is($t->mxp,0,'mxp off after deinitialization string');
is($t->user->id->_out_buf,'','MUD sent nothing after OK MXP');
is($t->user->_out_buf,'','MUD sent nothing after OK MXP');

done_testing();
