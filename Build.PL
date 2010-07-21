use strict;

use File::Spec;
use lib File::Spec->catdir('lib');          # use our self to install

# We use Module::Build to test & install itself.
use Module::Build;

# 

my $build = Module::Build->new(
  module_name => 'Av4',
  dist_version => '0.01',
  license     => 'gpl',
  requires => {
    'Digest::MD5'              => 0,
    'IO::Socket::INET'         => 0,
    'Compress::Zlib'           => 0,
    'YAML'                     => 0,
    'POE'                      => 0,
    'POE::XS::Loop::EPoll'     => 0,
    'POE::XS::Queue::Array'    => 0,
    'Inline::C'                => 0,
    'Log::Log4perl'            => 0,
    'Moose'                    => 0,
    'Cache::Memcached::Fast'   => 0,
  },
  recursive_test_files => 1,
  sign          => 0, 
  create_readme => 1,
  create_license => 1,
);

$build->create_build_script;
# vim:ts=2:sw=2:et:sta
