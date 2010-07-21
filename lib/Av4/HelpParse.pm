package Av4::HelpParse;
use strict;
use warnings;
use Fatal qw/open close/;
use Log::Log4perl qw(:easy);
use Av4::Ansi;
use Av4::Help;

our $areahelps;
our $log = Log::Log4perl->get_logger(__PACKAGE__);

sub areaparse {
    my $fn = shift;
    open my $F, '<', $fn;
    my @area;
    my $section      = 0;
    my $subsection   = 0;
    my $sectionlevel = 0;
    my $data         = '';
    my $lineno       = 0;
    my $log          = Log::Log4perl->get_logger(__PACKAGE__);
    while (<$F>) {
        my $line = $_;
        $lineno++;
        next if ( $line =~ /^\s*$/ );
        if ( !$section ) {    # looking for #SECTIONNAME
            die "Line $lineno: havent found any section name!\n"
              if ( $line !~ /^\#\w+\s*$/ );
            $section = $line;
            $section =~ s/^\#//g;
            $section =~ s/\s*$//g;
            $log->debug("Line $lineno: section $section");
            next;
        }
        if ( !$subsection ) {    # on help file, level + keywords
            die "Line $lineno: doesnt match number + letters + ~\n"
              unless ( my ( $level, $keywords ) = $line =~ /^\s*\-?(\d*)\s*(.*)\~\s*$/ );
            $log->debug("Line $lineno: Level $level keywords $keywords");
            $subsection   = $keywords;
            $sectionlevel = $level;
            next;
        }

        # for help, until line containing ~
        if ( $line =~ /^\s*\~\s*$/ ) {
            push(
                @area,
                Av4::Help->new(
                    level    => $sectionlevel,
                    keywords => $subsection,
                    data     => $data
                )
            );
            $subsection = 0;
            $data       = '';
            $log->debug("Line $lineno: Got help page for $subsection");
            next;
        }
        chomp($line);
        $data .= $line . "\r\n";
    }
    close $F;
    $areahelps = \@area;
    return \@area;
}

sub areahelp {
    my ( $helps, $which ) = @_;
    $which =~ s/[\x0d\x0a]//g;
    #$log->debug("areahelp: Searching for `$which`");
    foreach (@$helps) {
        return $_ if ( $_->keywords =~ /\b\Q$which\E/i );
    }
    #$log->debug("areahelp: No helps found for `$which`");
    return undef;
}

1;
