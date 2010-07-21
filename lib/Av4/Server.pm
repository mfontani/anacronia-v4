package Av4::Server;
use Moose;
use Av4::Help;
use Av4::User;

has 'helps' => (
    is       => 'rw',
    isa      => 'ArrayRef[Av4::Help]',
    required => 1,
    default  => sub { [] }
);
has 'inbuffer'  => ( is => 'rw', isa => 'HashRef', required => 1, default => sub { {} } );
has 'outbuffer' => ( is => 'rw', isa => 'HashRef', required => 1, default => sub { {} } );
has 'clients'   => (
    is       => 'rw',
    #isa      => 'ArrayRef[Av4::User]', # makes testcover die
    isa      => 'ArrayRef', # doesn't
    required => 1,
    default  => sub { [] }
);

has 'kernel' => ( is => 'rw', isa => 'Any', required => 1 );

has 'running' => ( is => 'rw', isa => 'Int', required => 1, default => 1 );

no Moose;
__PACKAGE__->meta->make_immutable();
1;
