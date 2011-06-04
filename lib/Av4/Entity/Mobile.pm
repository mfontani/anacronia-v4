package Av4::Entity::Mobile;
use strict;
use warnings;

use base 'Av4::Entity';

sub defaults {
    ( Av4::Entity->defaults, );
}

use Class::XSAccessor {
    constructor => 'new',
    accessors   => [
        qw/
          vnum
          /
    ],
};

# TODO hook here for behaviour based on input received
# sub print { }

sub random_command {

    #warn "Entity $_[0] (" . $_[0]->id . ") tick random command\n";
    if ( int( rand(5) ) == 0 ) {
        my $cmd = rand_command();
        push @{ $_[0]->queue }, $cmd;

        #warn "   -> rand command: $cmd\n";
    }
}

my @commands = qw/areas say shout help help who commands colors help stats help help hlist look n s w e u d ne se nw sw @goto/;
my @helps    = qw/help anacronia commands say shout colors who online stats shutdown/;

sub rand_command {
    my $ret = $commands[ rand @commands ];
    if ( $ret eq '@goto' ) {
        return $ret . ' ' . int( 30 + rand(20) );
    }
    $ret .= ' ';
    $ret .= $helps[ rand @helps ];
    return $ret;
}

1;
