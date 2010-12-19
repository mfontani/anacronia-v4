package Av4::Command;
use Av4::Utils qw/get_logger ansify/;

use Class::XSAccessor {
    constructor => '_new',
    accessors => [qw/name priority delays code/],

};

sub new {
    my $class = shift;
    $class->_new(
        # defaults
        name => '',
        priority => 0,
        delays => 0,
        code => sub {},
        # wanted options
        @_,
    );
}

sub exec {
    my $self = shift;
    my ( $kernel, $client, $user, $argstr ) = @_;

    $user->print( ansify( "&gCommand: &c" . $self->name . " &C$argstr\r\n" ) )
      unless (
        $self->name =~ /^\#\$\#/    # MCP commands
        || $self->name =~ /^\@/     # wiz commands
      );

    # 0 if shouldn't delay due to wrong parameters etc.
    my $rc = $self->code->( $kernel, $client, $user, $argstr, );
    $rc = -1 if ( !defined $rc );
    $rc = $rc >= 0 ? $self->delays : 0;
    return $rc;
}

1;
