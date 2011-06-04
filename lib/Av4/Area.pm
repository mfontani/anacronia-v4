package Av4::Area;
use strict;
use warnings;
use Class::XSAccessor {
    constructor => '_new',
    accessors   => [qw/id name author ranges resetmsg flags economy rooms mobiles/],
};

our %areas;

my $last_area_id = 0;

sub new {
    my $class = shift;
    my $area  = $class->_new(

        # defaults
        name     => 'Unnamed area',
        author   => 'Nobody',
        ranges   => [ 0, 0 ],
        resetmsg => 'The earth shakes slightly.',
        flags    => [],
        economy  => [],
        rooms    => [],
        mobiles  => [],

        # wanted options
        @_,
    );
    $area->id( $last_area_id++ ) unless $area->id;
    $areas{ $area->id } = $area;
    $area;
}

sub by_id {
    my $id = pop @_;
    warn "Area id $id not found\n" unless exists $areas{$id};
    return $areas{$id};
}

1;
