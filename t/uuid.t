use 5.006;
use strict;
use warnings;
use Test::More 0.92;

use Data::UUID::MT;
use List::AllUtils qw/uniq/;

sub _as_string {
  return uc join "-", unpack("H8H4H4H4H12", shift);
}

my @cases = (
  {},
  { version => '1' },
  { version => '4' },
  { version => '4s' },
); 

for my $c ( @cases ) {
  my $label = $c->{version} || '4 (default)';
  subtest "version => $label"  => sub {
    my $ug = Data::UUID::MT->new( %$c );
    my $version = $c->{version} || "4";
    my $uuid1= $ug->create;

    # structural test
    my $binary = unpack("B*", $uuid1);
    ok( defined $uuid1, "Created a UUID" );
    is( length $uuid1, 16, "UUID is 16 byte string" );
    is( substr($binary,64,2), "10", "variant field correct" );
    is( substr($binary,48,4),
        substr(unpack("B8", chr(substr($version,0,1))),4,4),
        "version field correct"
    );
    
    # uniqueness test
    my @uuids;
    push @uuids, $ug->create for 1 .. 10000;
    my @uniq = uniq @uuids;
    is( scalar @uniq, scalar @uuids, "Generated 10,000 unique UUIDs" );

    # sequence test
    my @seq;
    if ( $version eq "1" ) {
      # version 1 is time-low, time-mid, time-high-and-version
      @seq = map { substr($_,6,2) . substr($_,4,2) . substr($_,0,3) } @uuids;
    }
    else {
      # version 4 should be random except for version bits
      # version 4s should be sequential in the first 64 bits (albeit with
      # the version bits 'frozen')
      @seq = map { substr($_,0,8) } @uuids;
    }
    my @sorted = sort @seq;
    if ( $version eq "4" ) {
      ok( join("",@seq) ne join("",@sorted),
        "UUIDs are not ordered for version $version"
      );
    }
    else {
      ok( join("",@seq) eq join("",@sorted),
        "UUIDs are correctly ordered for version $version"
      );
    }
  }
}

done_testing;
# COPYRIGHT
