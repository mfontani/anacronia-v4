package Av4::Commands;
use strict;
use warnings;
use Av4::Command;
use Av4::Commands::Basic;
use Av4::Commands::Delegated;
use Av4::Commands::MCP;
use Av4::Commands::MXP;

our %commands;
__PACKAGE__->_add_mxp_commands();
__PACKAGE__->_add_mcp_commands();
__PACKAGE__->_add_basic_commands();
__PACKAGE__->_add_movement_commands();
__PACKAGE__->_add_delegated_commands();
__PACKAGE__->_add_admin_commands();

sub cmd_set {
    my ( $self, $what, $data ) = @_;
    $commands{ lc $what } = $data;
}

sub cmd_get {
    my ( $self, $what ) = @_;
    $commands{ lc $what };
}

sub cmd_exists {
    my ( $self, $which ) = @_;
    $which = lc $which;
    my $it = $self->cmd_get($which);
    return defined $it;
}

sub _add_mxp_commands {
    my $self = shift;

    # @mxp TEXT
    $self->cmd_set(
        '@mxp',
        Av4::Command->new(
            name     => '@mxp',
            priority => 10,
            code     => \&Av4::Commands::MXP::cmd_mxp,
            delays   => 0,
        ),
    );
}

sub _add_mcp_commands {
    my $self = shift;

    #   #$#mcp authentication-key: 18972163558 version: 1.0 to: 2.1
    $self->cmd_set(
        '#$#mcp',
        Av4::Command->new(
            name     => '#$#mcp',
            priority => 9910,
            code     => \&Av4::Commands::MCP::cmd_mcp_blank,
            delays   => 0,
        ),
    );

    #   #$#mcp-negotiate-can AUTHKEY package: PKGNAME min-version: MVER max-version: MXVER
    $self->cmd_set(
        '#$#mcp-negotiate-can',
        Av4::Command->new(
            name     => '#$#mcp-negotiate-can',
            priority => 9905,
            code     => \&Av4::Commands::MCP::cmd_mcp_negotiate_can,
            delays   => 0,
        ),
    );

    # #$#mcp-negotiate-end AUTHKEY
    $self->cmd_set(
        '#$#mcp-negotiate-end',
        Av4::Command->new(
            name     => '#$#mcp-negotiate-end',
            priority => 9904,
            code     => \&Av4::Commands::MCP::cmd_mcp_negotiate_end,
            delays   => 0,
        ),
    );

    #   #$#dns-com-awns-ping <authkey> id: <unique id>
    $self->cmd_set(
        '#$#dns-com-awns-ping',
        Av4::Command->new(
            name     => '#$#dns-com-awns-ping',
            priority => 9905,
            code     => \&Av4::Commands::MCP::cmd_mcp_dns_com_awns_ping,
            delays   => 0,
        ),
    );

    #   #$#dns-com-awns-ping-reply <authkey> id: <unique id>

    # test: @editname to trigger a dns-org-mud-moo-simpleedit command
    $self->cmd_set(
        '@editname',
        Av4::Command->new(
            name     => '@editname',
            priority => 8999,
            code     => \&Av4::Commands::MCP::cmd_at_editname,
            delays   => 0,
        ),
    );

}

sub _add_basic_commands {
    my $self = shift;
    $self->cmd_set(
        'shout',
        Av4::Command->new(
            name     => 'shout',
            priority => 50,
            code     => \&Av4::Commands::Basic::cmd_shout,
            delays   => 2.5,
        )
    );
    $self->cmd_set(
        'say',
        Av4::Command->new(
            name     => 'say',
            priority => 49,
            code     => \&Av4::Commands::Basic::cmd_say,
            delays   => 0.9,
        )
    );
    $self->cmd_set(
        'colors',
        Av4::Command->new(
            name     => 'colors',
            priority => 100,
            code     => \&Av4::Commands::Basic::cmd_colors,
            delays   => 1,
        )
    );
    $self->cmd_set(
        'help',
        Av4::Command->new(
            name     => 'help',
            priority => 100,
            code     => \&Av4::Commands::Basic::cmd_help,
            delays   => 1,
        )
    );
    $self->cmd_set(
        'hlist',
        Av4::Command->new(
            name     => 'hlist',
            priority => 100,
            code     => \&Av4::Commands::Basic::cmd_hlist,
            delays   => 1,
        )
    );
    $self->cmd_set(
        'look',
        Av4::Command->new(
            name     => 'look',
            priority => 120,
            code     => \&Av4::Commands::Basic::cmd_look,
            delays   => 1,
        )
    );
    $self->cmd_set(
        'who',
        Av4::Command->new(
            name     => 'who',
            priority => 80,
            code     => \&Av4::Commands::Basic::cmd_who,
            delays   => 2,
        )
    );
    $self->cmd_set(
        'commands',
        Av4::Command->new(
            name     => 'commands',
            priority => 990,
            code     => \&Av4::Commands::Basic::cmd_commands,
            delays   => 0,
        )
    );
    $self->cmd_set(
        'stats',
        Av4::Command->new(
            name     => 'stats',
            priority => 999,
            code     => \&Av4::Commands::Basic::cmd_stats,
            delays   => 0.2,
        )
    );
    $self->cmd_set(
        'areas',
        Av4::Command->new(
            name     => 'areas',
            priority => 900,
            code     => \&Av4::Commands::Basic::cmd_areas,
            delays   => 2,
        )
    );
    $self->cmd_set(
        'quit',
        Av4::Command->new(
            name     => 'quit',
            priority => 999,
            code     => \&Av4::Commands::Basic::cmd_quit,
            delays   => 0,
        )
    );
}

sub _add_movement_commands {
    my $self = shift;
    $self->cmd_set( 'n',
        Av4::Command->new( name => 'n', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'North' ) }, delays => 0.3, ) );
    $self->cmd_set( 'e',
        Av4::Command->new( name => 'e', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'East' ) }, delays => 0.3, ) );
    $self->cmd_set( 's',
        Av4::Command->new( name => 's', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'South' ) }, delays => 0.3, ) );
    $self->cmd_set( 'w',
        Av4::Command->new( name => 'w', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'West' ) }, delays => 0.3, ) );
    $self->cmd_set( 'u',
        Av4::Command->new( name => 'u', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'Up' ) }, delays => 0.3, ) );
    $self->cmd_set( 'd',
        Av4::Command->new( name => 'd', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'Down' ) }, delays => 0.3, ) );
    $self->cmd_set( 'ne',
        Av4::Command->new( name => 'ne', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'NorthEast' ) }, delays => 0.3, ) );
    $self->cmd_set( 'nw',
        Av4::Command->new( name => 'nw', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'NorthWest' ) }, delays => 0.3, ) );
    $self->cmd_set( 'se',
        Av4::Command->new( name => 'se', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'SouthEast' ) }, delays => 0.3, ) );
    $self->cmd_set( 'sw',
        Av4::Command->new( name => 'sw', priority => 1, code => sub { Av4::Commands::Basic::cmd_move( @_, 'SouthWest' ) }, delays => 0.3, ) );
}

sub _add_delegated_commands {
    my $self = shift;
    $self->cmd_set(
        'power',
        Av4::Command->new(
            name     => 'power',
            priority => 1,
            code     => \&Av4::Commands::Delegated::cmd_power,
            delays   => 5,
        )
    );
}

sub _add_admin_commands {
    my $self = shift;
    $self->cmd_set(
        'debug',
        Av4::Command->new(
            name     => 'debug',
            priority => 1,
            code     => \&Av4::Commands::Basic::cmd_debug,
        )
    );
    $self->cmd_set(
        '@goto',
        Av4::Command->new(
            name     => '@goto',
            priority => 9900,
            code     => \&Av4::Commands::Basic::cmd_goto,
            delays   => 0.5,
        )
    );
    $self->cmd_set(
        '@mpall',
        Av4::Command->new(
            name     => '@mpall',
            priority => 9900,
            code     => \&Av4::Commands::Basic::cmd_mpall,
        )
    );
    $self->cmd_set(
        '@shutdown',
        Av4::Command->new(
            name     => '@shutdown',
            priority => 9999,
            code     => \&Av4::Commands::Basic::cmd_shutdown,
        )
    );
}

1;
