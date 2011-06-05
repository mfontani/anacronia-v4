package Av4::AreaParse;
use strict;
use warnings;
use Fatal qw/open close/;
use utf8::all;
use Log::Log4perl qw(:easy);
use Av4::Ansi;
use Av4::Room;
use Av4::Area;
use Av4::Help;
use Av4::Entity::Mobile;
use JSON::XS qw<>;

our $helps = [];
our $areas = [];
our $log = Log::Log4perl->get_logger(__PACKAGE__);

sub parse_areas_from_dir {
    my $dir        = shift;
    my @area_files = <$dir/*.json>;
    warn "Parsing area files:", ( map { "\n  $_" } @area_files ), "\n";
    my @areas;
    for my $area_file (@area_files) {
        warn "Parsing area file $area_file..\n";
        my $area = area_file_parse($area_file);
        warn "    Parsed $area_file: " . scalar( @{ $area->{rooms} } ) . " rooms\n";
        push @areas, $area;
    }
    $areas = \@areas;
    return $areas;
}

sub area_file_parse {
    my $fn = shift;
    open my $F, '<', $fn;
    my $json = do { local $/ = undef; <$F>; };
    close $F;
    my $data = JSON::XS->new->utf8->allow_blessed->convert_blessed->decode($json);
    if ( exists $data->{helps} ) {
        for my $dhelp ( @{ $data->{helps} } ) {
            $dhelp->{data} = delete $dhelp->{text};
            push @$helps, Av4::Help->new( %$dhelp );
        }
        delete $data->{helps};
    }
    $data->{rooms} = [ map { Av4::Room->new( %$_ ) } @{ $data->{rooms} } ] if exists $data->{rooms};
    $data->{mobiles} = [ map { Av4::Entity::Mobile->new( Av4::Entity::Mobile->defaults, %$_ ) } @{ $data->{mobiles} } ]
      if exists $data->{mobiles};
    return Av4::Area->new( %$data, filename => $fn, );
}

sub areahelp {
    my ( $helps, $which ) = @_;
    $which =~ s/[\x0d\x0a]//g;

    foreach (@$helps) {
        return $_ if ( $which ~~ $_->keywords );
    }

    return;
}

1;
