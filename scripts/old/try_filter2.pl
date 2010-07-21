#!/usr/bin/perl -w
package main;
use strict;
use warnings;
use lib './lib';
use Av4::POE::Filter::NonData;
use YAML;
use File::Slurp qw/slurp/;
use 5.010_000;

my $datafile = shift;
die "$0: need datafile\n" if ( !defined $datafile );
my $data = data_received($datafile);
say "\e[2J";
say '#' x 72;
say "Data received:";
say '#' x 72;
print $data;
say '#' x 72;

{

    package My::Av4::Test;
    use Moose;
    has 'handled' => ( is => 'rw', isa => 'Bool', required => 1, );
    has 'telopt'  => ( is => 'rw', isa => 'Str',  required => 1, );
    has 'option'  => ( is => 'rw', isa => 'Str',  required => 1, );
    has 'data'    => ( is => 'rw', isa => 'Str',  required => 1, default => '' );
    no Moose;
    __PACKAGE__->meta->make_immutable();
}

my @telnetoptions;

my $filter = Av4::POE::Filter::NonData->new(
    'DO' => {
        'COMPRESS2' => sub {
            my ( $self, $telopt, $option ) = @_;
            push @telnetoptions,
              My::Av4::Test->new( handled => 1, telopt => $telopt, option => $option );
        },
    },
    'DONT' => {
        'COMPRESS2' => sub {
            my ( $self, $telopt, $option ) = @_;
            push @telnetoptions,
              My::Av4::Test->new( handled => 1, telopt => $telopt, option => $option );
        },
    },
    'WILL' => {
        'TTYPE' => sub {
            my ( $self, $telopt, $option ) = @_;
            push @telnetoptions,
              My::Av4::Test->new( handled => 1, telopt => $telopt, option => $option );
        },
    },
    'WONT' => {
        'TTYPE' => sub {
            my ( $self, $telopt, $option ) = @_;
            push @telnetoptions,
              My::Av4::Test->new( handled => 1, telopt => $telopt, option => $option );
        },
    },
    DEFAULT => sub {
        my ( $self, $telopt, $option, $_data ) = @_;
        $_data = '' if ( !defined $_data );
        push @telnetoptions,
          My::Av4::Test->new( handled => 0, telopt => $telopt, option => $option, data => $_data );
    },
);

# data received is parsed
$filter->get_one_start( [$data] );

# client asks for parsed data
my $parsed_data = $filter->get_one();

# results are shown
show_results();

exit;

sub show_results {
    say '#' x 72;
    say 'Telnet options parsed:';
    say '#' x 72;
    foreach my $opt (@telnetoptions) {
        my $databytes = join( ' ', map { ord $_ } split( '', $opt->data ) );
        say $opt->handled ? 'Handled' : 'Unhandled', ' ',
          Av4::POE::Filter::NonData->s_telopt( $opt->telopt ),    ' ',
          Av4::POE::Filter::NonData->s_teloption( $opt->option ), ' ',
          ' data: ', $databytes, ' >', $opt->data, '<';
    }
    say '#' x 72;
    say 'Returned data:';
    say '#' x 72;
    say Dump($parsed_data);
    say '#' x 72;
}

sub data_received {
    my $filename = shift;
    my @data     = slurp($filename);
    my $lineno   = 0;
    my $data     = '';
    foreach my $dataline (@data) {
        $lineno++;
        my ( $direction, $handle, $arrdata ) =
          $dataline =~ /^(Sent|Received)\s.*\s(.*)\:\s*\[([\d\,]+)\]\s*$/;
        if ( !defined $direction || !defined $handle || !defined $arrdata ) {
            die "Line $lineno: regexp didn't catch!\n";
        }
        next if ( $direction !~ /Received/i );
        my @arr = split( ',', $arrdata );
        $data .= pack( 'C*', @arr );
    }
    return $data;
}
