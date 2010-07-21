package Av4::Command;
use Moose;
use Av4::Utils qw/get_logger ansify/;

has 'name'     => ( is => 'ro', isa => 'Str', required => 1 );
has 'priority' => ( is => 'ro', isa => 'Int', required => 1, default => 0 );
has 'delays'   => ( is => 'ro', isa => 'Int', required => 1, default => 0 );
has 'code' => (
    is       => 'ro',
    isa      => 'CodeRef',
    required => 1,
    default  => sub {
        sub { }
    }
);

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

no Moose;
__PACKAGE__->meta->make_immutable();
1;
