#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use utf8;

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

is($t->analyze('123'),'123','ascii data OK');
is($t->analyze('æßð'),'æßð','utf8 data OK');
is($t->analyze('¹²³€½'),'¹²³€½','utf8 data OK');
is($t->analyze('½¾'),'½¾','utf8 data OK');
is($t->analyze('@łe¶ŧ←↓→øþ'),'@łe¶ŧ←↓→øþ','utf8 data OK');
is($t->analyze('æßðđŋħjĸł'),'æßðđŋħjĸł','utf8 data OK');
is($t->analyze('«»¢“”nµ'),'«»¢“”nµ','utf8 data OK');
is($t->analyze('Σὲ γνωρίζω ἀπὸ τὴν κόψη'),'Σὲ γνωρίζω ἀπὸ τὴν κόψη','greek ok');
is($t->analyze('გთხოვთ ახლავე გაიაროთ რეგისტრაცია Unicode-ის მეათე საერთაშორისო'),'გთხოვთ ახლავე გაიაროთ რეგისტრაცია Unicode-ის მეათე საერთაშორისო','georgian ok');
is($t->analyze('สิบสองกษัตริย์ก่อนหน้าแลถัดไป'),'สิบสองกษัตริย์ก่อนหน้าแลถัดไป','thai ok');
is($t->analyze('ᚻᛖ ᚳᚹᚫᚦ ᚦᚫᛏ ᚻᛖ ᛒᚢᛞᛖ ᚩᚾ ᚦᚫᛗ ᛚᚪᚾᛞᛖ ᚾᚩᚱᚦᚹᛖᚪᚱᛞᚢᛗ ᚹᛁᚦ ᚦᚪ ᚹᛖᛥᚫ'),'ᚻᛖ ᚳᚹᚫᚦ ᚦᚫᛏ ᚻᛖ ᛒᚢᛞᛖ ᚩᚾ ᚦᚫᛗ ᛚᚪᚾᛞᛖ ᚾᚩᚱᚦᚹᛖᚪᚱᛞᚢᛗ ᚹᛁᚦ ᚦᚪ ᚹᛖᛥᚫ','runes ok');

#is($t->analyze(''),'','xxx ok');

done_testing();
