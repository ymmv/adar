# in case Test::More ain't there
BEGIN {
    eval { require Test::More; };
    print "1..0\n" and exit if $@;
}

use strict;
use Test::More;
use File::Find;
use lib qw( ./lib ../lib );

my @modules;
find(
    sub {
        return unless /\.pm$/;
        local $_ = $File::Find::name;
        print STDERR "$_\n";
        s!/!::!g;
        s/\.pm$//;
        s/^lib:://;
        push
          @modules,
          $_;
    },
    'lib'
);

plan tests => scalar @modules;

use_ok($_) for sort @modules;

