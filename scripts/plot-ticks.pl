#!/usr/bin/env perl
use lib './inc/lib/perl5', './lib';
use common::sense;
use Chart::Clicker;
use Chart::Clicker::Data::Series;
use Chart::Clicker::Data::DataSet;
use Chart::Clicker::Renderer::Point;
use Chart::Clicker::Axis;
use Chart::Clicker::Axis::DateTime;
use Text::CSV_XS;
use utf8::all;
use autodie qw<open close>;
use Getopt::Long;

my $seconds_per_command_tick = shift or die "Need number of seconds per commands and flush ticks.\n";
my $seconds_per_flush_tick   = shift or die "Need number of seconds per commands and flush ticks.\n";

print "Graphs based on commands tick of $seconds_per_command_tick and flush tick of $seconds_per_flush_tick\n";

sub csv_to_array {
    my $filename = shift;
    my $csv      = Text::CSV_XS->new();
    open my $fh, '<', $filename;
    my $nline = 0;
    my @data;
    while ( my $row = $csv->getline($fh) ) {
        push @data, $row if $nline;
        $nline++;
    }
    $csv->eof or $csv->error_diag;
    close $fh;
    return (
        keys   => [ map { $_->[0] } @data ],
        values => [ map { $_->[1] } @data ],
    );
}

my $cc = Chart::Clicker->new(
    width  => 1000,
    height => 600,
);
$cc->title->text("Commands & Flush; timings in seconds");

my %data_flush    = csv_to_array('tick_flush.csv');
my %data_commands = csv_to_array('tick_commands.csv');
$cc->add_to_datasets(
    Chart::Clicker::Data::DataSet->new(
        series => [
            Chart::Clicker::Data::Series->new( name => 'Flush',    %data_flush ),
            Chart::Clicker::Data::Series->new( name => 'Commands', %data_commands ),
        ]
    )
);

## Markers don't seem to work :(
{

    # Tick commands should take at most 0.1
    my $tick_commands_marker = Chart::Clicker::Data::Marker->new(
        color => Graphics::Color::RGB->new( red         => 1, blue     => .10, green => .10, alpha => 1 ),
        brush => Graphics::Primitive::Brush->new( width => 3, line_cap => 'round', ),
        value => $seconds_per_command_tick,
    );

    # Tick flush should take at most 0.05
    my $tick_flush_marker = Chart::Clicker::Data::Marker->new(
        color => Graphics::Color::RGB->new( red         => .10, blue     => 1, green => .10 ),
        brush => Graphics::Primitive::Brush->new( width => 3,   line_cap => 'round', ),
        value => $seconds_per_flush_tick,
    );
    {
        my $d = $cc->get_context('default');
        $d->add_marker($_) for ( $tick_commands_marker, $tick_flush_marker );
    }
}

my $context = Chart::Clicker::Context->new( name => 'Players' );
$cc->add_to_contexts($context);
$cc->add_to_datasets(
    Chart::Clicker::Data::DataSet->new(
        context => 'Players',
        series  => [ Chart::Clicker::Data::Series->new( name => 'Players', csv_to_array('tick_players.csv') ), ],
    )
);

# X axis is done via datetime
$cc->contexts->{default}->domain_axis(
    Chart::Clicker::Axis::DateTime->new(
        orientation => 'horizontal',
        position    => 'bottom',
        format      => '%H:%M:%S.%3N',
    )
);

# X axis is done via datetime
$cc->contexts->{Players}->domain_axis(
    Chart::Clicker::Axis::DateTime->new(
        orientation => 'horizontal',
        position    => 'bottom',
        format      => '%H:%M:%S.%3N',
    )
);

# Y axis is done via custom sprintf
$cc->contexts->{default}->range_axis(
    Chart::Clicker::Axis->new(
        orientation => 'vertical',
        position    => 'left',
        format      => '%.5f',
    )
);

my $renderer = Chart::Clicker::Renderer::Point->new( markers => 1 );
$cc->set_renderer($renderer);

$cc->write_output('ticks.png');
qx{open ticks.png};

