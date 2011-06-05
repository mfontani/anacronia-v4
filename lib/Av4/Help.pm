package Av4::Help;
use strict;
use warnings;
use Av4::Ansi;
use Class::XSAccessor {
    constructor => '_new',
    accessors   => [qw/level keywords data data_ansified/],
};

sub new {
    my $class = shift;
    my $ohelp = $class->_new(

        # defaults
        level         => 0,
        keywords      => '',
        data          => '',
        data_ansified => '',

        # wanted options
        @_,
    );
    if ( !$ohelp->data_ansified ) {
        $ohelp->data_ansified( Av4::Ansi::ansify( $ohelp->data ) );
    }
    return $ohelp;
}

1;
