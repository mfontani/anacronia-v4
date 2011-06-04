package Av4::AreaParse;
use strict;
use warnings;
use Fatal qw/open close/;
use Log::Log4perl qw(:easy);
use Av4::Room;
use Av4::Area;
use Av4::Entity::Mobile;

our $areas;
our $log = Log::Log4perl->get_logger(__PACKAGE__);

sub areaparse {
    my $dir        = shift;
    my @area_files = <$dir/*.are>;
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
    my $details = {
        name     => 'Unnamed area',
        author   => 'Nobody',
        ranges   => [ 0, 999 ],
        resetmsg => 'You seem to hear a noise coming from below.',
        flags    => [],
        economy  => [ 0, 0 ],
        rooms    => [],
    };
    my $lineno          = 0;
    my $log             = Log::Log4perl->get_logger(__PACKAGE__);
    my $current_section = '';
    my $room;
    my $mob;
    my $tmp_desc = '';
    my $exit;
    my $do_extra;

    while (<$F>) {
        my $line = $_;
        $lineno++;

        next if ( $line =~ /^\s*$/ && !$current_section );    # non-significant whitespace before #ROOMS etc

        if ( !$current_section ) {
            if ( $line =~ /^#AREA\s*([^~]+)~/ )   { $details->{name}   = $1; next }
            if ( $line =~ /^#AUTHOR\s*([^~]+)~/ ) { $details->{author} = $1; next }
            if ( $line =~ /^#RANGES\s*([\d\s]+)\$/ ) { $details->{ranges} = [ split( /\s+/, $1 ) ]; next }
            if ( $line =~ /^#RESETMSG\s*([^~]+)~/ ) { $details->{resetmsg} = $1; next }
            if ( $line =~ /^#FLAGS\s*([\d\s]+)~/ )   { $details->{flags}   = [ split( /\s+/, $1 ) ]; next }
            if ( $line =~ /^#ECONOMY\s*([\d\s]+)~/ ) { $details->{economy} = [ split( /\s+/, $1 ) ]; next }
            if ( $line =~ /^#\s*(\w+)\s*$/ ) { $current_section = uc $1; next }
            if ( $line =~ /^#\$$/ )          { $current_section = undef; next }
            die "Line $lineno: unknown token: '$line'\n";
        }

        if ( $current_section eq 'ROOMS' ) {
            if ( $line =~ /^#(\d+)\s*$/ ) {
                if ( defined $room ) {
                    my $oroom = Av4::Room->new(%$room);
                    push @{ $details->{rooms} }, $oroom;
                    $room     = undef;
                    $tmp_desc = '';
                }
                if ( $line =~ /^#0$/ ) {
                    $current_section = undef;
                    next;
                }
            }
            $room->{data} .= $line if ( defined $room && $room->{data} !~ /\Q$line\E$/gms );
            if ( !defined $room && $line =~ /^#(\d+)\s*$/ ) { $room = { vnum => $1, data => $line, }; next }
            if ( !exists $room->{name} && $line =~ /^([^~]+)~$/ ) { $room->{name} = $1; next }
            if ( !exists $room->{desc} && $line !~ /^~$/ ) { $tmp_desc .= $line; next }
            if ( !exists $room->{desc} && $line =~ /^~$/ ) { $room->{desc} = $tmp_desc; next }
            if ( !exists $room->{flags} && $line =~ /^(\d+\s+)+$/ ) { $room->{flags} = [ split( /\s+/, $1 ) ]; next }

            # Now the room's exits
            if ( !$exit && $line =~ /^(D)(\d+)$/ ) {
                $exit = { door => $2, };
                next;
            }
            if ($exit) {
                if ( !exists $exit->{desc} ) {
                    if ( $line !~ /^~$/ ) {
                        $tmp_desc .= $line;
                    }
                    else {
                        $exit->{desc} = $tmp_desc;
                        $tmp_desc .= '';
                    }
                    next;
                }
                if ( !exists $exit->{keywords} && $line =~ /^([^~]*)~$/ ) {
                    $exit->{keywords} = [ split( /\s+/, $1 ) ];
                    next;
                }
                if ( !exists $exit->{flags} && $line =~ /^([-\d\s]+)$/ ) {
                    my @flags = split( /\s+/, $line );

                    # locks, key, to_vnum, vdir, orig_door, distance, pulltype, pull
                    $exit->{locks}   = $flags[0];
                    $exit->{key}     = $flags[1];
                    $exit->{to_vnum} = $flags[2];
                    $exit->{flags}   = [@flags];
                    next;
                }
                if ( $line =~ /^(D)(\d+)$/ || $line =~ /^S$/ ) {
                    push @{ $room->{exits} }, $exit;
                    $exit = undef;
                    $lineno--;
                    redo;
                }
                if ( $line =~ /^E$/ ) {
                    $do_extra = 1;
                    next;
                }
                if ($do_extra) {
                    if ( $line !~ /^~$/ ) {
                        $tmp_desc .= $line;
                    }
                    else {
                        push @{ $room->{extra} }, $tmp_desc;
                        $tmp_desc .= '';
                        $do_extra = 0;
                    }
                    next;
                }
                if ( $line =~ /^M/ ) {

                    # not yet parsed
                    next;
                }
                die "Line $lineno: section ROOMS/EXIT, unknown token: '$line'\n";
            }
            if ( $line =~ /^M/ ) {
                next;
            }
            if ( $line =~ /^S$/ ) {
                next;
            }
            die "Line $lineno: section ROOMS, unknown token: '$line'\n";
        }

        if ( $current_section eq 'MOBILES' ) {
            if ( $line =~ /^#(\d+)\s*$/ ) {
                if ($mob) {
                    my $omob = Av4::Entity::Mobile->new( Av4::Entity::Mobile->defaults, %$mob );
                    push @{ $details->{mobiles} }, $omob;
                    $mob      = undef;
                    $tmp_desc = '';
                }
                if ( $line =~ /^#0$/ ) {
                    $current_section = undef;
                    next;
                }
            }
            $mob->{data} .= $line if ( defined $mob && $mob->{data} !~ /\Q$line\E$/gms );
            if ( !defined $mob && $line =~ /^#(\d+)\s*$/ ) { $mob = { vnum => $1, data => $line, }; next }
            if ( !exists $mob->{keywords} && $line =~ /^([^~]+)~$/ ) { $mob->{keywords} = [ split( /\s+/, $1 ) ]; next }
            if ( !exists $mob->{name} && $line =~ /^([^~]+)~$/ ) { $mob->{name} = $1; next }
            if ( !exists $mob->{short} && $line !~ /^~$/ ) { $tmp_desc .= $line; next }
            if ( !exists $mob->{short} && $line =~ /^~$/ ) { $mob->{short} = $tmp_desc; $tmp_desc = ''; next }
            if ( !exists $mob->{desc} && $line !~ /^~$/ ) { $tmp_desc .= $line; next }
            if ( !exists $mob->{desc} && $line =~ /^~$/ ) { $mob->{desc} = $tmp_desc; $tmp_desc = ''; next }
            if ( !exists $mob->{flags} ) { $mob->{flags} = [ split( /\s+/, $line ) ]; next }
            if ( !exists $mob->{damage} ) { $mob->{damage} = split( /\s+/, $line ); next }
            if ( !exists $mob->{xp} )      { $mob->{xp}      = [ split( /\s+/, $line ) ]; next }
            if ( !exists $mob->{dump1} )   { $mob->{dump1}   = [ split( /\s+/, $line ) ]; next }
            if ( !exists $mob->{stats} )   { $mob->{stats}   = [ split( /\s+/, $line ) ]; next }
            if ( !exists $mob->{bonuses} ) { $mob->{bonuses} = [ split( /\s+/, $line ) ]; next }
            if ( !exists $mob->{dump2} )   { $mob->{dump2}   = [ split( /\s+/, $line ) ]; next }
            if ( !exists $mob->{dump3} )   { $mob->{dump3}   = [ split( /\s+/, $line ) ]; next }
            die "Line $lineno: section MOBILES, unknown token: '$line'\n" . "Data so far: " . YAML::Dump($mob);
        }

        if ( $current_section eq 'RESETS' ) {
            if ( $line =~ /^S$/ ) {
                $current_section = undef;
                next;
            }

            # Letter EXTRA arg1 arg2 arg3?
            if ( $line =~ /^R\s+(\d+)\s+(\d+)\s+(\d+)\s*$/ ) {

                # Room reset: ?? vnum ??
                next;
            }
            if ( $line =~ /^M\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/ ) {

                # MOB reset: ?? mob_vnum ?? room_vnum
                if ( my ($mob) = grep { $_->{vnum} eq $2 } @{ $details->{mobiles} } ) {
                    $mob->{in_room} = $4;
                    next;
                }
                else {
                    die "Line $lineno: mob VNUM $2 was not found in file: '$line'\n";
                }
            }
            if ( $line =~ /^E\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/ ) {

                # EQUIP MOB reset: ?? obj_vnum ?? location_num
                next;
            }
            if ( $line =~ /^G\s+(\d+)\s+(\d+)\s+(\d+)\s*$/ ) {

                # INVENTORY MOB reset: ?? obj_vnum ??
                next;
            }
            if ( $line =~ /^D\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/ ) {

                # DOOR reset: ?? room_vnum ?? ??
                next;
            }
            die "Line $lineno: section RESETS, unknown token: '$line'\n";
        }
        die "Line $lineno: unknown section '$current_section' unknown token: '$line'\n";
    }
    close $F;
    return Av4::Area->new(%$details);
}

1;
