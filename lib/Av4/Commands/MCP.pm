package Av4::Commands::MCP;
use Av4::Utils qw/get_logger/;
require Av4::Commands;
require Av4;
require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(cmd_mcp_blank);

## FIXME the below needs tested with a client. this is EXPERIMENTAL!

=for DONE

Done so far:
- parsing #$#mcp authentication-key
  - stores key on Av4::User
  - need to use that key when sending MCP commands back
- parsing #$#mcp-negotiate-can
  - storing all packages supported by clients along with versions on Av4::User
- replying with supported packages:
  - mcp-cord
- command stats:
  - gives back list of packages the server knows the client supports

Packages advertised:
 - mcp-cord
 - dns-com-awns-ping

Packages supported:
 - dns-com-awns-ping
   - replies with same ID to the ping

To DO packages:
 - dns-com-awns-ping-reply
   - the mud may send dns-com-awns-ping to client if client doesn't answer for X seconds
   - that would be the client's response
 - dns-com-awns-rehash
   - provides info on the commands the server can parse, to be used with command completion
 - dns-org-kubik-prompt
   - sends prompt separately


=cut

=for LATER

Need to implement from http://www.awns.com/mcp/ too.

Implemented in PMC:

- '#$#mcp authentication-key: 360128 version: 2.1 to: 2.1'
- '#$#mcp-negotiate-can 360128 min-version: 2.1 max-version: 2.1 package: mcp-negotiate-can'
- '#$#mcp-negotiate-can 360128 min-version: 1.0 max-version: 1.0 package: dns-com-awns-ping'
- '#$#mcp-negotiate-can 360128 min-version: 1.0 max-version: 1.0 package: dns-de-spin-theland-prompt'
- '#$#mcp-negotiate-can 360128 min-version: 1.0 max-version: 1.0 package: dns-org-cubik-prompt'
- '#$#mcp-negotiate-can 360128 min-version: 1.0 max-version: 1.0 package: dns-com-awns-rehash'
- '#$#mcp-negotiate-can 360128 min-version: 1.0 max-version: 1.0 package: dns-mud-moo-org-simpleedit'
- '#$#mcp-negotiate-can 360128 min-version: 1.0 max-version: 1.0 package: dns-com-vmoo-client'

Implemented in ZMud (from http://www.zuggsoft.com/zmud/mcp-dev.htm):
- mcp without cords
- mcp-negotiate (required)
- dns-org-mud-moo-simpleedit:
  - server sends list of strings to client, client edits multiline then sends back the lines
  - http://www.moo.mud.org/mcp/simpleedit.html
  - http://www.awns.com/mcp/packages/README.dns-org-mud-moo-simpleedit
- dns-com-awns-displayurl (http://www.awns.com/mcp/packages/README.dns-com-awns-displayurl)
- dns-com-awns-ping (http://www.awns.com/mcp/packages/README.dns-com-awns-ping)
- dns-com-vmoo-client (http://www.vmoo.com/support/moo/mcp-specs/#vm-client)
- dns-com-zuggsoft-mxp => sends MXP via MCP
- dns-com-zuggsoft-msp => sends MSP via MCP

Implemented in Gnoemoe:

- '#$#mcp-negotiate-can EBkg7r package: mcp-negotiate min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-can EBkg7r package: dns-com-awns-status min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-can EBkg7r package: dns-com-vmoo-client min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-can EBkg7r package: dns-com-awns-ping min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-can EBkg7r package: dns-nl-icecrew-playerdb min-version: 1.0 max-version: 1.1 '
- '#$#mcp-negotiate-can EBkg7r package: dns-nl-icecrew-userlist min-version: 1.0 max-version: 1.1 '
- '#$#mcp-negotiate-can EBkg7r package: dns-nl-icecrew-mcpreset min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-can EBkg7r package: dns-nl-icecrew-serverinfo min-version: 1.0 max-version: 1.1 '
- '#$#mcp-negotiate-can EBkg7r package: dns-com-vmoo-userlist min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-can EBkg7r package: dns-org-mud-moo-simpleedit min-version: 1.0 max-version: 1.0 '
- '#$#mcp-negotiate-end EBkg7r '


From http://www.moo.mud.org/mcp/mcp2.html:

MCP defines two standard packages. The first of these, the mcp-negotiate package, is a critical
part of the MCP startup sequence, and all MCP implementations are required to implement it. The
second, the mcp-cord package, allows the creation of multiple communications channels within MCP's
single channel. Implementations are strongly suggested, but not required, to provide support for
cords. Its presence in the standard reflects this suggestion, and serves as an example of a package
built on top of MCP.

Implementations are not permitted to wait for receipt of an mcp-negotiate-end message before
sending mcp-negotiate-can messages for packages they support.

The mcp-negotiate package consists of two messages:
 * mcp-negotiate-can, which is used to inform the other side of a connection of the packages
   supported by an implementation, and the range of versions supported.
 * mcp-negotiate-end, which indicates that an implementation has sent mcp-negotiate-can messages
   for all packages it supports.

**CORDS**
Three operations are possible on cords:
  they may be created,
  have messages sent along them,
  and they may be destroyed.
Each cord has an associated unique (to the opening participant) identifier and a type. The type is
similar to an MCP package name -- it determines the messages which may be sent along a cord, and
is used by the recipient of an open request to attach the cord to an appropriate object.

Cord IDs are normally prefixed with R if coming from a client, and with I if coming from server.

 Open a cord:
    #$#mcp-cord-open AUTHKEY _id: CORDID _type: CORDTYPE
    Example: #$#mcp-cord-open 3487 _id: I12345 _type: whiteboard
 Message through cord:
    #$#mcp-cord AUTHKEY _id: CORDID _message: MESSAGE [ARGUMENTS KEY: VALUE PAIRS]
    Example: #$#mcp-cord 3487 _id: I12345 _message: delete-stroke stroke-id: 12321
 Close a cord:
    #$#mcp-cord-closed AUTHKEY _id: CORDID
    Example: #$#mcp-cord-closed 3487 _id: I12345

** dns-com-awns-ping **
http://www.awns.com/mcp/packages/README.dns-com-awns-ping

The package dns-com-awns-ping allows both client and server to test the latency of a user's
connection, a rough indication of net-lag.

dns-com-awns-ping is symmetric, with both ends of the connection
supporting the following messages:

    #$#dns-com-awns-ping <authkey> id: <unique id>
    #$#dns-com-awns-ping-reply <authkey> id: <unique id>

In order to estimate the round-trip-time for a message the client (or server) should first
generate a unique id and make a note of the current system time (Tping), then send the
dns-com-awns-ping message.  At the other end of the connection the recipient should immediately
reply with dns-com-awns-ping-reply substituting the value of id.  Upon receipt of the
dns-com-awns-ping-reply message the client (or server) should make a note of the current system
time (Treply), and can then estimate the round-trip-time as:

    rtt = Treply - Tping

A different unique id should generated for each subsequent dns-com-awns-ping message.

** dns-com-awns-rehash **
http://www.awns.com/mcp/packages/README.dns-com-awns-rehash

** dns-org-kubik-prompt **
http://mcp.cubik.org/packages/prompt/

server to client:
    dns-org-cubik-prompt-is prompt: "whatever the prompt is>"
      sends the prompt
client to server:
    dns-org-cubik-prompt-request
      re-requests prompt to be sent

** dns-nl-icecrew-serverinfo **
http://www.icecrew.nl/files//koemoe/mcp/p_serverinfo.xhtml

client to server:
  #$#dns-nl-icecrew-serverinfo-get AUTHID

server to client (no newlines should be sent):
  #$#dns-nl-icecrew-serverinfo-set AUTHID name: STRING homepage: STRING location: STRING
  admin: STRING contact: STRING charset: STRING language: STRING system: STRING logo: STRING

example (no newlines are actually sent):
  #$#dns-nl-icecrew-serverinfo 3453 name: FantasyMOO homepage: http://www.fantasymoo.nl/
  location: Groningen admin: "Jesse van den Kieboom" contact: "allanon@fantasymoo.nl"
  charset: "ISO-8859-15" language: "Nederlands/Dutch"
  system: "Linux vorrion 2.6.8.1-3-386 #1 Thu Nov 18 11:47:33 UTC 2004 i586 GNU/Linux"
  logo: "http://www.fantasymoo.nl/images/moo_logo.svg;http://www.fantasymoo.nl/images/moo_logo.png"


** dns-nl-icecrew-playerdb **
http://www.icecrew.nl/files//koemoe/mcp/p_playerdb.xhtml
others from http://www.icecrew.nl/files//koemoe/mcp/index.xhtml



=cut

# for command: #$#mcp *
sub cmd_mcp_blank {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info("Got MCP blank command: `$argstr`");

    # authentication-key: 480676 version: 2.1 to: 2.1
    my @subcommands =
      split( /\s/, $argstr, 2 );    # 'authentication-key:', '480676 version: 2.1 to: 2.1'
    if ( !defined $subcommands[0] ) {
        $log->info('IGNORING MCP command with no params');
        return [0];
    }
    $subcommands[1] = '' if ( !defined $subcommands[1] );

    # TODO: dispatch table?
    if ( $subcommands[0] eq 'authentication-key:' ) {
        $log->info('MCP => cmd_mcp_authentication_key');
        return cmd_mcp_authentication_key( $client, $user, $subcommands[1] );
    }
    else {
        $log->info( 'UNKNOWN MCP COMMAND: >', $subcommands[0], '< => UNHANDLED!' );
    }
    return [0];
}

# for command: #$#mcp authentication-key: AUTHKEY *
# INTERNAL: only called by cmd_mcp_blank
sub cmd_mcp_authentication_key {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();

    # 480676 version: 2.1 to: 2.1
    $log->info("Got MCP auth command: `$argstr`");
    my ( $authkey, $options ) = split( /\s/, $argstr, 2 );    # '480676', 'version: 2.1 to: 2.1'
    if ( !defined $authkey ) {
        $log->info('IGNORING MCP AUTH command with no authkey');
        return [0];
    }
    $user->mcp_authentication_key($authkey);
    $log->info( 'MCP AUTH for user ', $user, ': ', $authkey );

    # Advertises the server's support for mcp-cord and whatever else is supported
    my $output = join(
        '',
        "\r\n",
        '#$#mcp-negotiate-can ', $authkey,
        ' package: mcp-negotiate min-version: 1.0 max-version: 2.0',
        "\r\n",
        '#$#mcp-negotiate-can ', $authkey, ' package: mcp-cord min-version: 1.0 max-version: 1.0',
        "\r\n",

        # other supported packages
        '#$#mcp-negotiate-can ', $authkey,
        ' package: dns-com-awns-ping min-version: 1.0 max-version: 1.0',
        "\r\n",
        '#$#mcp-negotiate-can ', $authkey,
        ' package: dns-mud-moo-org-simpleedit min-version: 1.0 max-version: 1.0',
        "\r\n",
        '#$#mcp-negotiate-end ', $authkey, "\r\n",

        # that's it
    );
    return [ 0, $output ];
}

# for command: #$#mcp-negotiate-end AUTHKEY
sub cmd_mcp_negotiate_end {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info("Got MCP NEGOTIATE END: `$argstr`");

    # first word is authkey
    my $authkey;
    ( $authkey, $argstr ) = split( /\s/, $argstr, 2 );
    $authkey = '' if ( !defined $authkey );
    if ( $user->mcp_authentication_key ne $authkey ) {
        $log->info("MCP NEGOTIATE-END sent with wrong auth string, IGNORING");
        return [0];
    }
    return [0];
}

# for command: #$#mcp-negotiate-can AUTHKEY package: PKGNAME min-version: MVER max-version: MXVER
sub cmd_mcp_negotiate_can {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info("Got MCP NEGOTIATE CAN: `$argstr`");

    # first word is authkey
    my $authkey;
    ( $authkey, $argstr ) = split( /\s/, $argstr, 2 );
    $authkey = '' if ( !defined $authkey );
    if ( $user->mcp_authentication_key ne $authkey ) {
        $log->info("MCP NEGOTIATE-CAN sent with wrong auth string, IGNORING");
        return [0];
    }

    # $argstr = package: PKGNAME min-version: MVER max-version: MXVER
    # $argstr = min-version: MVER max-version: MXVER package: PKGNAME
    # etc.
    my @tokens = split( /\s/, $argstr );
    if ( scalar @tokens % 2 == 1 ) {
        $log->info("MCP NEGOTIATE-CAN sent an odd number of tokens, IGNORING");
        return [0];
    }

    # interested in the following:
    my $verbatim_package_found = 0;
    my $package_name;
    my $verbatim_min_version_found = 0;
    my $min_version;
    my $verbatim_max_version_found = 0;
    my $max_version;

    for ( my $i = 0 ; $i < $#tokens ; $i += 2 ) {
        if ( $tokens[$i] eq 'package:' ) {
            if ( !defined $tokens[ $i + 1 ] ) {
                $log->info("MCP NEGOTIATE-CAN sent 'package:' without name after, IGNORING");
                return [0];
            }
            $verbatim_package_found = 1;
            $package_name           = $tokens[ $i + 1 ];
        }
        elsif ( $tokens[$i] eq 'min-version:' ) {
            if ( !defined $tokens[ $i + 1 ] ) {
                $log->info("MCP NEGOTIATE-CAN sent 'min-version:' without it after, IGNORING");
                return [0];
            }
            $verbatim_min_version_found = 1;
            $min_version                = $tokens[ $i + 1 ];
        }
        elsif ( $tokens[$i] eq 'max-version:' ) {
            if ( !defined $tokens[ $i + 1 ] ) {
                $log->info("MCP NEGOTIATE-CAN sent 'max-version:' without it after, IGNORING");
                return [0];
            }
            $verbatim_max_version_found = 1;
            $max_version                = $tokens[ $i + 1 ];
        }
        else {
            $log->info( "MCP NEGOTIATE-CAN IGNORING because of unknown token: ", $tokens[$i] );
            return [0];
        }
    }

    # bail out if the syntax isn't recognised
    if ( !$verbatim_package_found ) {
        $log->info("MCP NEGOTIATE-CAN hasn't sent 'package:', IGNORING");
        return [0];
    }
    if ( !$verbatim_min_version_found ) {
        $log->info("MCP NEGOTIATE-CAN hasn't sent 'min-version:', IGNORING");
        return [0];
    }
    if ( !$verbatim_max_version_found ) {
        $log->info("MCP NEGOTIATE-CAN hasn't sent 'max-version:', IGNORING");
        return [0];
    }

    # all seems good
    $log->info( "MCP: looks like ", $package_name, " is supported, ", "versions ", $min_version, " to ", $max_version );

    # debug?
    #$user->print(
    #    "$Av4::Utils::ANSI{'&C'}MCP $Av4::Utils::ANSI{'&g'}ACK$Av4::Utils::ANSI{'&w'}'ing " .
    #    "your support of MCP package $Av4::Utils::ANSI{'&W'}$package_name versions " .
    #    "$Av4::Utils::ANSI{'&r'}$min_version$Av4::Utils::ANSI{'&w'}-$Av4::Utils::ANSI{'&r'}$max_version\r\n"
    #) if (0);
    $user->mcp_packages_supported->{$package_name} = [ $min_version, $max_version ];
    return [0];
}

# for command: #$#dns-com-awns-ping <authkey> id: <unique id>
sub cmd_mcp_dns_com_awns_ping {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();
    $log->info("Got MCP DNS-COM-AWNS-PING: `$argstr`");

    # first word is authkey
    my $authkey;
    ( $authkey, $argstr ) = split( /\s/, $argstr, 2 );
    $authkey = '' if ( !defined $authkey );
    if ( $user->mcp_authentication_key ne $authkey ) {
        $log->info("MCP DNS-COM-AWNS-PING sent with wrong auth string, IGNORING");
        return [0];
    }

    # $argstr = package: PKGNAME min-version: MVER max-version: MXVER
    # $argstr = min-version: MVER max-version: MXVER package: PKGNAME
    # etc.
    my @tokens = split( /\s/, $argstr );
    if ( scalar @tokens % 2 == 1 ) {
        $log->info("MCP DNS-COM-AWNS-PING sent an odd number of tokens, IGNORING");
        return [0];
    }

    # interested in the following:
    my $verbatim_id_found = 0;
    my $ping_id;

    for ( my $i = 0 ; $i < $#tokens ; $i += 2 ) {
        if ( $tokens[$i] eq 'id:' ) {
            if ( !defined $tokens[ $i + 1 ] ) {
                $log->info("MCP DNS-COM-AWNS-PING sent 'id:' without name after, IGNORING");
                return [0];
            }
            $verbatim_id_found = 1;
            $ping_id           = $tokens[ $i + 1 ];
        }
        else {
            $log->info( "MCP DNS-COM-AWNS-PING IGNORING because of unknown token: ", $tokens[$i] );
            return [0];
        }
    }

    # bail out if the syntax isn't recognised
    if ( !$verbatim_id_found ) {
        $log->info("MCP DNS-COM-AWNS-PING hasn't sent 'id:', IGNORING");
        return [0];
    }

    # answer the ping
    $log->info( 'MCP DNS-COM-AWNS-PING: replied to ping id ', $ping_id );
    return [ 0,
        '#$#dns-com-awns-ping-reply ' . $user->mcp_authentication_key . " id: $ping_id\r\n" . '#$#dns-com-awns-ping-reply ' . "id: $ping_id\r\n" ];
}

sub cmd_at_editname {
    my ( $client, $user, $argstr ) = @_;
    my $log = get_logger();

    if ( !$user->mcp_authentication_key ) {
        return [ 0, "$Av4::Utils::ANSI{'&r'}Command available only to MCP users\r\n" ];
    }

=for example

    #$#dns-org-mud-moo-simpleedit-content 3487 reference: #73.name
       name: "Joe's name" type: string content*: "" _data-tag: 12345
    #$#* 12345 content: Joe
    #$#:

[21:11] [MCP] < #$#dns-org-mud-moo-simpleedit-content OH2dKd reference: "str:#2.description" name: Wizard.description type: string content*: "" _data-tag: 11662825430
[21:11] [MCP] < #$#* 11662825430 content: You see a wizard who chooses not to reveal eir true appearance.
[21:11] [MCP] < #$#: 11662825430
[21:11] [MCP] > #$#dns-org-mud-moo-simpleedit-set OH2dKd reference: str:#2.description type: string content*: "" _data-tag: myVKUsP69m
[21:11] [MCP] > #$#* myVKUsP69m content: You see a wizard who chooses not to reveal eir true appearance.
[21:11] [MCP] > #$#: myVKUsP69m

[21:18] [MCP] < #$#dns-org-mud-moo-simpleedit-content CQyHS0 reference: "str:#1.name" name: You.name type: string content*: "" _data-tag: 115562534
[21:18] [MCP] < #$#* 115562534 content: yourname
[21:18] [MCP] < #$#: 115562534

=cut

    my $datatag = int rand(123947987) + 1;
    $log->info( "Sending user's name via MCP: >", $user->name, '< tag: ', $datatag );

    #$user->print(
    #    '#$#dns-org-mud-moo-simpleedit-content ', $user->mcp_authentication_key,
    #    ' reference: "str:#1.name" name: You.name type: string content*: ""',
    #    ' _data-tag: ', $datatag, "\n",
    #    '#$#* ', $datatag, ' content: ', $user->name ? $user->name : 'yourname', "\n",
    #    '#$#: ', $datatag, "\n",
    #);
    return [ 0,
            '#$#dns-org-mud-moo-simpleedit-content '
          . $user->mcp_authentication_key
          . ' reference: "str:#2.description" name: Wizard.description type: string content*: "" _data-tag: 11662825430'
          . "\x0D\x0A"
          . '#$#* 11662825430 content: You see a wizard who chooses not to reveal eir true appearance.'
          . "\x0D\x0A"
          . '#$#: 11662825430'
          . "\x0D\x0A"
          . "\x0D\x0A" ];
}

1;
