package Av4::Command;
use strict;
use warnings;
use constant DEBUG_TIME_TAKEN_BY_COMMAND => 1;
use Time::HiRes qw<gettimeofday tv_interval time>;
require Av4::Utils;    # for ANSI

use Class::XSAccessor {
    constructor => '_new',
    accessors   => [qw/name priority delays code/],
};

our %time_taken_by_command;

sub new {
    my $class = shift;
    $class->_new(

        # defaults
        name     => '',
        priority => 0,
        delays   => 0,
        code     => sub { },

        # wanted options
        @_,
    );
}

sub exec {
    my $t0 = [gettimeofday] if DEBUG_TIME_TAKEN_BY_COMMAND;
    my ( $self, $client, $user, $argstr ) = @_;
    my $bufsize = ref $user eq 'Av4::Entity::Player' ? length( $user->buffer // '' ) : 0;

    $user->print( $Av4::Utils::ANSI{'&g'}
          . "Command: "
          . $Av4::Utils::ANSI{'&c'}
          . $self->name . ' '
          . $Av4::Utils::ANSI{'&C'}
          . "$argstr"
          . $Av4::Utils::ANSI{'&^'}
          . "\r\n" )
      unless (
        $self->name =~ /^\#\$\#/    # MCP commands
        || $self->name =~ /^\@/     # wiz commands
      );

    # 0 if shouldn't delay due to wrong parameters etc.
    my $rc = $self->code->( $client, $user, $argstr, );
    $rc->[0] = -1 if ( !defined $rc->[0] );
    $rc->[0] = $rc->[0] >= 0 ? $self->delays : 0;
    $user->print( "\r\n" . $rc->[1] . "\r\n" ) if defined $rc->[1];
    $bufsize = ( ref $user eq 'Av4::Entity::Player' ? length $user->buffer : 0 ) - $bufsize;
    push @{ $time_taken_by_command{ $self->name } }, [ time, tv_interval( $t0, [gettimeofday] ), $bufsize ] if DEBUG_TIME_TAKEN_BY_COMMAND;
    return $rc->[0];
}

1;
