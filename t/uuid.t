use 5.006;
use strict;
use warnings;
use Test::More 0.92;

use Data::UUID::MT;

my $ug = Data::UUID::MT->new;

my $uuid1= $ug->create;

ok( defined $uuid1, "Created a UUID (default version)" );
is( length $uuid1, 16, "UUID is 16 byte string" );

my $next = $ug->iterator;
ok( defined $next, "Got UUID iterator" );
my $uuid2 = $next->();

isnt( $uuid1, $uuid2, "Iterator generated a different UUID" );

done_testing;
# COPYRIGHT
