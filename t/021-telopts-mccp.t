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
    sub print {
        diag("Printed: @_");
        join('',@_);
    }
    sub id {
        Av4::User::PushWriteable::Mocked->new;
    }
    sub new { bless {}, $_[0] }
}

can_ok ('Av4::TelnetOptions', qw/analyze/);
can_ok ('Av4::User::Mocked', $_ ) for qw/new print/;

my $t = Av4::TelnetOptions->new( user => Av4::User::Mocked->new );
ok($t,'Av4::TelnetOptions created');

is($t->mccp,0,'default no mccp');
eq_or_diff(
    $t->analyze(
        sprintf("%c%c%c",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DO,
            Av4::Telnet::TELOPT_COMPRESS2,
        ),
    ),
    '',
    'simple mccp initialization is filtered'
);
is($t->mccp,1,'mccp on after initialization string');
isnt($t->zstream, 0, 'zstream is not 0');
isnt($t->zstream, '', 'zstream is not empty');
is(
    $t->user->id->_out_buf,
    sprintf("%c%c%c%c%c",
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SB,
        Av4::Telnet::TELOPT_COMPRESS2,
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SE,
    ),
    'MUD sent IAC SB COMPRESS2 IAC SE'
);

eq_or_diff(
    $t->analyze(
        sprintf("%c%c%c",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DONT,
            Av4::Telnet::TELOPT_COMPRESS2,
        ),
    ),
    '',
    'simple mccp deinitialization is filtered'
);
is($t->mccp,0,'mccp off after deinitialization string');
is($t->zstream, 0, 'zstream is 0');
is($t->user->id->_out_buf,'','_out_buf is empty');

$t = Av4::TelnetOptions->new( user => Av4::User::Mocked->new );
ok($t,'Av4::TelnetOptions created');

is($t->mccp,0,'default no mccp');
eq_or_diff(
    $t->analyze(
        sprintf("te%c%c%cst",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DO,
            Av4::Telnet::TELOPT_COMPRESS2,
        ),
    ),
    'test',
    'mccp initialization between two pieces of text is filtered'
);
is($t->mccp,1,'mccp on after initialization string');
isnt($t->zstream, 0, 'zstream is not 0');
isnt($t->zstream, '', 'zstream is not empty');
is(
    $t->user->id->_out_buf,
    sprintf("%c%c%c%c%c",
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SB,
        Av4::Telnet::TELOPT_COMPRESS2,
        Av4::Telnet::TELOPT_IAC,
        Av4::Telnet::TELOPT_SE,
    ),
    'MUD sent IAC SB COMPRESS2 IAC SE'
);

eq_or_diff(
    $t->analyze(
        sprintf("te%c%c%cst",
            Av4::Telnet::TELOPT_IAC,
            Av4::Telnet::TELOPT_DONT,
            Av4::Telnet::TELOPT_COMPRESS2,
        ),
    ),
    'test',
    'mccp deinitialization between two strings is filtered'
);
is($t->mccp,0,'mccp off after deinitialization string');
is($t->zstream, 0, 'zstream is 0');
is($t->user->id->_out_buf,'','_out_buf is empty');

done_testing();
