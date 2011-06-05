package Av4::Room;
use strict;
use warnings;
use Class::XSAccessor {
    constructor => '_new',
    accessors   => [qw/data vnum name desc desc_ansi flags exits extra entities clients/],
};
use Av4::Ansi;

our $last_auto_vnum = 1_000_000;

our %rooms;

our @dir_name       = qw<North East South West Up   Down NorthEast NorthWest SouthEast SouthWest Somewhere>;
our @rev_dir_name   = qw<South West North East Down Up   SouthWest SouthEast NorthWest NorthEast Somewhere>;
our %dir_number     = map { $dir_name[$_] => $_ } 0 .. $#dir_name;
our %rev_dir_number = map { $rev_dir_name[$_] => $_ } 0 .. $#rev_dir_name;

sub dir_name {
    return 'unknown' unless defined $_[0];
    return 'UNKNOWN' unless defined $dir_name[ $_[0] ];
    return $dir_name[ $_[0] ];
}

sub dir_number {
    return -1 unless defined $_[0] && exists $dir_number{ $_[0] };
    return $dir_number{ $_[0] };
}

sub rev_dir_name {
    return 'unknown' unless defined $_[0];
    return 'UNKNOWN' unless defined $rev_dir_name[ $_[0] ];
    return $rev_dir_name[ $_[0] ];
}

sub new {
    my $class = shift;
    my $room  = $class->_new(

        # defaults
        vnum      => 0,
        name      => '',
        desc      => '',
        desc_ansi => '',
        flags     => [],
        exits     => [],
        extra     => [],
        entities  => [],
        clients   => [],

        # wanted options
        @_,
    );
    $room->desc_ansi( Av4::Ansi::ansify( $room->desc ) )
      unless $room->desc_ansi;
    $room->vnum( $last_auto_vnum++ ) unless $room->vnum;
    $rooms{ $room->vnum } = $room;
    $room;
}

sub by_id {
    my $id = pop @_;
    warn "Room id $id not found\n" unless exists $rooms{$id};
    return $rooms{$id};
}

sub broadcast {
    my ( $self, $actor, $message, $selfmessage ) = @_;
    my $actor_id = $actor->id;
    for my $player ( @{ $self->entities } ) {
        if ( $player->id eq $actor_id ) {
            if ($selfmessage) {
                $player->print($selfmessage);
            }
            next;
        }
        $player->print($message);
        $player->prompt;
    }
}

1;
