package Av4::Commands;
use strict;
use warnings;
use Av4::Command;
use Av4::Commands::Basic;
use Av4::Commands::MCP;

use Class::XSAccessor {
    constructor => '_new',
    accessors => [qw/commands keywords data/],
};

sub new {
    my $class = shift;
    my $self = $class->_new(
        # defaults
        commands => {},
        keywords => '',
        data => '',
        # wanted options
        @_,
    );
    $self->_add_mcp_commands();
    $self->_add_basic_commands();
    $self->_add_admin_commands();
    $self;
}

#    handles  => {
#        all_cmds   => 'keys',
#        cmd_get    => 'get',
#        cmd_set    => 'set',
#    },

sub cmd_set {
    my ($self,$what,$data) = @_;
    $self->commands->{lc $what} = $data;
}
sub cmd_get {
    my ($self,$what) = @_;
    $self->commands->{lc $what};
}

sub exists {
    my ( $self, $which ) = @_;
    $which = lc $which;
    my $it = $self->cmd_get($which);
    return defined $it;
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
            delays   => 2,
        )
    );
    $self->cmd_set(
        'colors',
        Av4::Command->new(
            name     => 'help',
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
        'who',
        Av4::Command->new(
            name     => 'who',
            priority => 80,
            code     => \&Av4::Commands::Basic::cmd_who,
            delays   => 5,
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
            delays   => 0,
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
        '@shutdown',
        Av4::Command->new(
            name     => '@shutdown',
            priority => 9999,
            code     => \&Av4::Commands::Basic::cmd_shutdown,
        )
    );
}

1;
