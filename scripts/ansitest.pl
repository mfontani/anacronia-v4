use strict;
use warnings;
use lib './inc/lib/perl5', './lib';
use Av4::Ansi;

print "type a smaug-coloured string\n";
while (<>) {
    print "ASCII   : $_\n";
    my $ansified = Av4::Ansi::ansify( $_ . "\n" );
    chomp($ansified);
    print "ANSI    : ", $ansified, "\n";
    $ansified =~ s/\033/\\e/gm;
    $ansified =~ s/\x0A/\\r/gm;
    $ansified =~ s/\x0D/\\n/gm;
    print "ANSITXT : ", $ansified, "\n";
    print "\n";
}
