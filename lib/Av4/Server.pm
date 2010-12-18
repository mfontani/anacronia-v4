package Av4::Server;
use strict;
use warnings;
use Av4::Help;
use Av4::User;

use Class::XSAccessor {
    constructor => '_new',
    accessors => [ qw/helps inbuffer outbuffer clients kernel running/ ],
};

sub new {
    my $class = shift;
    $class->_new(
        # defaults
        helps => [],
        inbuffer => {},
        outbuffer => {},
        clients => [],
        running => 1,
        kernel => undef,
        # wanted options
        @_,
    );
}

1;
