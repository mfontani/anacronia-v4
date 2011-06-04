package Av4::Utils;
use strict;
use warnings;

use Cache::Memcached::Fast;
use Digest::MD5 qw/md5_hex/;

use Log::Log4perl ();

use Av4::Ansi;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(get_logger ansify);

our %ANSI;

BEGIN {
    for (qw<x r g y b p c w>) {
        $ANSI{"&$_"} = Av4::Ansi::ansify("&$_");
        $ANSI{"^$_"} = Av4::Ansi::ansify("^$_");
        my $u = uc $_;
        $ANSI{"&$u"} = Av4::Ansi::ansify("&$u");
        $ANSI{"^$u"} = Av4::Ansi::ansify("^$u");
    }
    $ANSI{'&^'} = Av4::Ansi::ansify('&^');
    $ANSI{'^&'} = Av4::Ansi::ansify('^&');
}

our $memcached_hits   = 0;
our $memcached_misses = 0;
our $memoized_hits    = 0;
our $memoized_misses  = 0;

our $memd = new Cache::Memcached::Fast(
    {
        servers         => [ { address => '127.0.0.1:11211', } ],
        namespace       => 'av4:',
        connect_timeout => 0.2,
        io_timeout      => 0.2,
        compress_ratio  => 0.9,
    }
);

sub get_logger {
    my ($subroutine) = ( caller(1) )[3];
    return Log::Log4perl->get_logger($subroutine);
}

our %ansify_cache;

sub ansify {
    my ( $str, $status ) = @_;
    if ( length $str <= 4096 ) {
        if ( exists $ansify_cache{$str} ) {
            $memoized_hits++;
            return $ansify_cache{$str};
        }
        $memoized_misses++;
        $ansify_cache{$str} = Av4::Ansi::ansify( $str, $status );
        return $ansify_cache{$str};
    }
    my $md5 = md5_hex($str);
    my $hit = $memd->get($md5);
    if ($hit) { $memcached_hits++; return $hit; }
    $memcached_misses++;
    warn "Memcached MISS on $str";
    my $ansified = Av4::Ansi::ansify( $str, $status );
    $memd->set( $md5, $ansified );
    return $ansified;
}

1;

__END__
# ### pre memcached:
# # spent 2.42s (35.3ms+2.39) within Av4::Utils::ansify which was called 8149 times, avg 297µs/call:
# # 3649 times (15.8ms+889ms) by Av4::User::broadcast at line 86 of lib/Av4/User.pm, avg 248µs/call
# # 2601 times (11.2ms+473ms) by Av4::Commands::Basic::cmd_who at line 62 of lib/Av4/Commands/Basic.pm, avg 186µs/call
# #  861 times (3.62ms+194ms) by Av4::broadcast at line 308 of lib/Av4.pm, avg 229µs/call
# #  367 times (1.67ms+67.7ms) by Av4::Command::exec at line 22 of lib/Av4/Command.pm, avg 189µs/call
# #  147 times (706µs+671ms) by Av4::Commands::Basic::cmd_help at line 106 of lib/Av4/Commands/Basic.pm, avg 4.57ms/call
# #   96 times (441µs+23.1ms) by Av4::User::dispatch_command at line 158 of lib/Av4/User.pm, avg 246µs/call
# #   96 times (412µs+13.6ms) by Av4::User::broadcast at line 83 of lib/Av4/User.pm, avg 146µs/call
# #   82 times (374µs+23.1ms) by Av4::Commands::Basic::cmd_who at line 59 of lib/Av4/Commands/Basic.pm, avg 287µs/call
# #   82 times (350µs+8.95ms) by Av4::Commands::Basic::cmd_who at line 74 of lib/Av4/Commands/Basic.pm, avg 113µs/call
# #   42 times (195µs+10.3ms) by Av4::Commands::Basic::cmd_stats at line 119 of lib/Av4/Commands/Basic.pm, avg 250µs/call
# #   42 times (188µs+5.98ms) by Av4::Commands::Basic::cmd_stats at line 152 of lib/Av4/Commands/Basic.pm, avg 147µs/call
# #   42 times (182µs+5.50ms) by Av4::Commands::Basic::cmd_stats at line 133 of lib/Av4/Commands/Basic.pm, avg 135µs/call
# #   42 times (181µs+2.89ms) by Av4::Commands::Basic::cmd_stats at line 135 of lib/Av4/Commands/Basic.pm, avg 73µs/call
# sub ansify {
# 15  8149    31.1ms  8149    2.39s       &Av4::Ansi::ansify;
#     # spent  2.39s making 8149 calls to Av4::Ansi::ansify, avg 293µs/call
# 16                  }
# 
# ### post memcached (with md5 key based on string):
# # spent 1.71s (377ms+1.33) within Av4::Utils::ansify which was called 32693 times, avg 52µs/call:
# # 19791 times (227ms+800ms) by Av4::User::broadcast at line 86 of lib/Av4/User.pm, avg 52µs/call
# #  7340 times (81.4ms+258ms) by Av4::Commands::Basic::cmd_who at line 62 of lib/Av4/Commands/Basic.pm, avg 46µs/call
# #  1796 times (22.0ms+88.7ms) by Av4::Command::exec at line 22 of lib/Av4/Command.pm, avg 62µs/call
# #   890 times (11.6ms+47.8ms) by Av4::Commands::Basic::cmd_help at line 106 of lib/Av4/Commands/Basic.pm, avg 67µs/call
# #   780 times (9.19ms+44.3ms) by Av4::broadcast at line 308 of lib/Av4.pm, avg 69µs/call
# #   538 times (6.51ms+18.8ms) by Av4::User::broadcast at line 83 of lib/Av4/User.pm, avg 47µs/call
# #   504 times (6.15ms+23.3ms) by Av4::User::dispatch_command at line 158 of lib/Av4/User.pm, avg 58µs/call
# #   209 times (2.96ms+7.96ms) by Av4::Commands::Basic::cmd_who at line 74 of lib/Av4/Commands/Basic.pm, avg 52µs/call
# #   209 times (2.33ms+7.40ms) by Av4::Commands::Basic::cmd_who at line 59 of lib/Av4/Commands/Basic.pm, avg 47µs/call
# #   159 times (2.19ms+17.3ms) by Av4::Commands::Basic::cmd_stats at line 119 of lib/Av4/Commands/Basic.pm, avg 122µs/call
# #   159 times (2.49ms+6.41ms) by Av4::Commands::Basic::cmd_stats at line 133 of lib/Av4/Commands/Basic.pm, avg 56µs/call
# #   159 times (1.76ms+6.23ms) by Av4::Commands::Basic::cmd_stats at line 135 of lib/Av4/Commands/Basic.pm, avg 50µs/call
# #   159 times (1.81ms+5.48ms) by Av4::Commands::Basic::cmd_stats at line 152 of lib/Av4/Commands/Basic.pm, avg 46µs/call
# sub ansify {
# 32  32693   37.3ms              my ($str,$status) = @_;
# 33  32693   170ms   32693   69.1ms      my $md5 = md5_hex($str);
#     # spent  69.1ms making 32693 calls to Digest::MD5::md5_hex, avg 2µs/call
# 34  32693   1.28s   32693   1.14s       my $hit = $memd->get($md5);
#     # spent  1.14s making 32693 calls to Cache::Memcached::Fast::get, avg 35µs/call
# 35  32693   113ms               return $hit if $hit;
# 36  397 1.74ms  397 105ms       my $ansified = Av4::Ansi::ansify($str,$status);
#     # spent   105ms making 397 calls to Av4::Ansi::ansify, avg 265µs/call
# 37  397 20.1ms  397 18.0ms      $memd->set($md5,$ansified);
#     # spent  18.0ms making 397 calls to Cache::Memcached::Fast::set, avg 45µs/call
# 38  397 1.53ms              return $ansified;
# 39                  }

