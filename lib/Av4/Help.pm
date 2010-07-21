package Av4::Help;
use Moose;
has 'level'    => ( is => 'rw', isa => 'Num', required => 1, );
has 'keywords' => ( is => 'rw', isa => 'Str', required => 1, );
has 'data'     => ( is => 'rw', isa => 'Str', required => 1, );
__PACKAGE__->meta->make_immutable();
no Moose;
1;
