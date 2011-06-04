package Av4::Server;
use strict;
use warnings;

use Class::XSAccessor {
    constructor => '_new',
    accessors   => [qw/helps areas inbuffer outbuffer entities clients running/],
};

sub new {
    my $class = shift;
    $class->_new(

        # defaults
        helps     => [],
        areas     => [],
        inbuffer  => {},
        outbuffer => {},
        entities  => [],
        clients   => [],
        running   => 1,

        # wanted options
        @_,
    );
}

sub client_by_id {
    my ( $self, $id ) = @_;
    for ( @{ $self->clients } ) {
        return $_ if $_->id eq $id;
    }
    return;
}

1;
