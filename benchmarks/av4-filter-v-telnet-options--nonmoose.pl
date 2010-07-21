#!/usr/bin/perl -w
package main;
use strict;
use warnings;
use lib './lib';
use Benchmark qw/:all/;
use Av4::POE::Filter::NonData;
use Av4::POE::Filter::NonDataNew;
use Av4::Telnet;
use Net::Telnet::Options;

# test results: handled or default, option handled, sub-option and sb data
my @nondata_parsed    = ();
my @nondatanew_parsed = ();
my @telopt_parsed     = ();

## telnet data to be parsed
my $origdatachunk = sprintf(
    "%c%c%cTEST",    #"%c%c%cTEST%c%c%c",
    Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WILL(), Av4::Telnet::TELOPT_NAWS(),

    #Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WONT(), Av4::Telnet::TELOPT_TTYPE(),
) x 10;

## nondata object:
my $nondata = Av4::POE::Filter::NonData->new(
    WILL => {
        NAWS => sub {
            my ( $self, $telopt, $option ) = @_;
            push @nondata_parsed, { handled => 1, telopt => $telopt, option => $option };
        },
    },
    DEFAULT => sub {
        my ( $self, $telopt, $option ) = @_;
        push @nondata_parsed, { handled => 0, telopt => $telopt, option => $option };
    },
);

my $nondatanew = Av4::POE::Filter::NonDataNew->new(
    WILL => {
        NAWS => sub {
            my ( $self, $telopt, $option ) = @_;
            push @nondatanew_parsed, { handled => 1, telopt => $telopt, option => $option };
        },
    },
    DEFAULT => sub {
        my ( $self, $telopt, $option ) = @_;
        push @nondatanew_parsed, { handled => 0, telopt => $telopt, option => $option };
    },
);

my $nto = Net::Telnet::Options->new(
    NAWS => {
        WILL => sub {

            #my ( $self, $telopt, $option ) = @_;
            push @telopt_parsed, { handled => 1, telopt => 'will', option => 'naws' };
        },
    },
);

my $result = timethese(
    10_000,
    {
#        'Av4::POE::Filter::NonData' => sub { my $chunk = $origdatachunk; using_nondata($chunk); },
        'Av4::POE::Filter::NonDataNew' =>
          sub { my $chunk = $origdatachunk; using_nondata_new($chunk); },
        'Net::Telnet::Options' => sub { my $chunk = $origdatachunk; using_telopts($chunk); },
    }
);
cmpthese($result);

#warn "Telopts nondata:    ", scalar grep { $_->{handled} } @nondata_parsed,    "\n";
warn "Telopts nondatanew: ",(scalar grep { $_->{handled} } @nondatanew_parsed), "\n";
warn "Telopts telopts:    ",(scalar grep { $_->{handled} } @telopt_parsed),     "\n";

sub using_nondata {
    my $data = shift;
    $nondata->get_one_start( [$data] );
    die "nondata didn't find any option!" if ( !@nondata_parsed );
}

sub using_nondata_new {
    my $data = shift;
    $nondatanew->get_one_start( [$data] );
    die "nondata_new didn't find any option!" if ( !@nondatanew_parsed );
}

sub using_telopts {
    my $data = shift;
    while ( $data =~ /\xFF/ ) {
        $data = $nto->answerTelnetOpts( undef, $data );
    }
    die "telopts didn't find any option!" if ( !@telopt_parsed );
}

__END__

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        WILL => {
            NAWS => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option ) = @_;
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option);
        },
    );
    $filter->get_one_start([
        sprintf("%c%c%cTEST%c%c%c",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WILL(), Av4::Telnet::TELOPT_NAWS(),
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WONT(), Av4::Telnet::TELOPT_TTYPE(),
        )
    ]);
    ok (@parsed == 2, "Found and parsed two options");
    ok ($parsed[0]->handled == 1, 'first option was parsed');
    ok ($parsed[0]->telopt == Av4::Telnet::TELOPT_WILL(), 'first option was WILL');
    ok ($parsed[0]->option == Av4::Telnet::TELOPT_NAWS(), 'first option was NAWS');
    ok ($parsed[1]->handled == 0, 'second option was defaulted');
    ok ($parsed[1]->telopt == Av4::Telnet::TELOPT_WONT(), 'second option was WONT');
    ok ($parsed[1]->option == Av4::Telnet::TELOPT_TTYPE(), 'first option was TTYPE');
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq 'TEST',"Weeded out two options and got text only") or diag("Got >", $text->[0], "< instead of TEST");
}

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        WILL => {
            NAWS => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option ) = @_;
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option);
        },
    );
    $filter->get_one_start([
        sprintf("%c%c%cTEST%ctest%c%c",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WILL(), Av4::Telnet::TELOPT_NAWS(),
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WONT(), Av4::Telnet::TELOPT_TTYPE(),
        )
    ]);
    ok (@parsed == 1, "Found and parsed one option");
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq
        sprintf("TEST%ctest%c%c",
        Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WONT(), Av4::Telnet::TELOPT_TTYPE()),
        "Weeded out one option and got text only, with split IAC") or diag("Got >", $text->[0], "< instead of expected");
}

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        WILL => {
            NAWS => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option ) = @_;
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option);
        },
    );
    $filter->get_one_start([
        sprintf("%c%c%cTE%c%cST123",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WILL(), Av4::Telnet::TELOPT_NAWS(),
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_IAC(),
        )
    ]);
    ok (@parsed == 1, "Found and parsed one option");
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq sprintf("TE%cST123", Av4::Telnet::TELOPT_IAC()),
        "Weeded out one option and got text only, with one IAC") or diag("Got >", $text->[0], "< instead of expected");
}

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        SB => {
            NAWS => sub {
                my ( $self, $telopt, $option, $data ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option,data=>$data);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option ) = @_;
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option);
        },
    );
    $filter->get_one_start([
        sprintf("TE%c%c%c%c%c%c%c%c%cST123",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SB(), Av4::Telnet::TELOPT_NAWS(),
            0,80,0,24,
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SE(),
        )
    ]);
    ok (@parsed == 1, "Found and parsed one option");
    ok ($parsed[0]->data eq sprintf("%c%c%c%c",0,80,0,24), "Got right NAWS size") or diag (
        "Got ", join (' ', map {ord $_} split('', $parsed[0]->data)), " instead"
    );
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq "TEST123", "Weeded out one option and got text only") or diag("Got >", $text->[0], "< instead of expected");
}

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        SB => {
            TTYPE => sub {
                my ( $self, $telopt, $option, $data ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option,data=>$data);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option ) = @_;
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option);
        },
    );
    $filter->get_one_start([
        sprintf("TE%c%c%c%cWIZARD%c%cST123",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SB(), Av4::Telnet::TELOPT_TTYPE(),
            0, Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SE(),
        )
    ]);
    ok (@parsed == 1, "Found and parsed one option");
    ok ($parsed[0]->data eq sprintf("%cWIZARD",0), "Got right TTYPE") or diag (
        "Got ", join (' ', map {ord $_} split('', $parsed[0]->data)), " instead of WIZARD"
    );
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq "TEST123", "Weeded out one option and got text only") or diag("Got >", $text->[0], "< instead of expected");
}

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        DO => {
            COMPRESS2 => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        WILL => {
            TTYPE => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        SB => {
            TTYPE => sub {
                my ( $self, $telopt, $option, $data ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option,data=>$data);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option ) = @_;
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option);
        },
    );
    $filter->get_one_start([
        sprintf("TE" . "%c%c%c%c" . "%c%c%c%c" . "%c%c%c%c" . "%s%c%c" . "%c%cST123",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_DO(), Av4::Telnet::TELOPT_COMPRESS2(), 10,
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WILL(), Av4::Telnet::TELOPT_TTYPE(), 10,
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SB(), Av4::Telnet::TELOPT_TTYPE(), 0,
            'mushclient', Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SE(),
            10, 13,
        )
    ]);
    ok (@parsed == 3, "Found and parsed three options");
    ok ($parsed[0]->telopt == Av4::Telnet::TELOPT_DO(), 'first telopt was DO');
    ok ($parsed[0]->option == Av4::Telnet::TELOPT_COMPRESS2(), 'first option was COMPRESS2');
    ok ($parsed[1]->telopt == Av4::Telnet::TELOPT_WILL(), 'second telopt was WILL');
    ok ($parsed[1]->option == Av4::Telnet::TELOPT_TTYPE(), 'second option was TTYPE');
    ok ($parsed[2]->telopt == Av4::Telnet::TELOPT_SB(), 'third telopt was SB');
    ok ($parsed[2]->option == Av4::Telnet::TELOPT_TTYPE(), 'third option was TTYPE');
    ok ($parsed[2]->data eq sprintf("%cmushclient",0),'TTYPE is [0]mushclient');
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq sprintf("TE%c%c%c%cST123",10,10,10,13), "Weeded out one option and got text only")
        or diag("Got >", $text->[0], "< instead of expected");
}

{
    my @parsed;
    my $filter = Av4::POE::Filter::NonData->new(
        DO => {
            COMPRESS2 => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        WILL => {
            TTYPE => sub {
                my ( $self, $telopt, $option ) = @_;
                push @parsed, My::Av4::Test->new(handled=>1,telopt=>$telopt,option=>$option);
            },
        },
        DEFAULT => sub {
            my ( $self, $telopt, $option, $data ) = @_;
            $data = '' if (!defined $data);
            push @parsed, My::Av4::Test->new(handled=>0,telopt=>$telopt,option=>$option,data=>$data);
        },
    );
    $filter->get_one_start([
        sprintf("TE" . "%c%c%c%c" . "%c%c%c%c" . "%c%c%c%c" . "%s%c%c" . "%c%cST123",
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_DO(), Av4::Telnet::TELOPT_COMPRESS2(), 10,
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_WILL(), Av4::Telnet::TELOPT_TTYPE(), 10,
            Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SB(), Av4::Telnet::TELOPT_TTYPE(), 0,
            'mushclient', Av4::Telnet::TELOPT_IAC(), Av4::Telnet::TELOPT_SE(),
            10, 13,
        )
    ]);
    ok (@parsed == 3, "Found and parsed three options");
    ok ($parsed[0]->telopt == Av4::Telnet::TELOPT_DO(), 'first telopt was DO');
    ok ($parsed[0]->option == Av4::Telnet::TELOPT_COMPRESS2(), 'first option was COMPRESS2');
    ok ($parsed[1]->telopt == Av4::Telnet::TELOPT_WILL(), 'second telopt was WILL');
    ok ($parsed[1]->option == Av4::Telnet::TELOPT_TTYPE(), 'second option was TTYPE');
    ok ($parsed[2]->telopt == Av4::Telnet::TELOPT_SB(), 'third telopt was SB');
    ok ($parsed[2]->option == Av4::Telnet::TELOPT_TTYPE(), 'third option was TTYPE');
    ok ($parsed[2]->data eq sprintf("%cmushclient",0),'TTYPE is [0]mushclient');
    my $text = $filter->get_one();
    ok (@$text, "Got results from ->get_one()");
    ok (@$text == 1, "Got one result only from ->get_one()");
    ok ($text->[0] eq sprintf("TE%c%c%c%cST123",10,10,10,13), "Weeded out one option and got text only")
        or diag("Got >", $text->[0], "< instead of expected");
}
