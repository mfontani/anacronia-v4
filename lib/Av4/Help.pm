package Av4::Help;
use strict;
use warnings;
use Class::XSAccessor {
    constructor => '_new',
    accessors   => [qw/level keywords data data_ansified/],
};

sub new {
    my $class = shift;
    $class->_new(

        # defaults
        level         => 0,
        keywords      => '',
        data          => '',
        data_ansified => '',

        # wanted options
        @_,
    );
}

1;
