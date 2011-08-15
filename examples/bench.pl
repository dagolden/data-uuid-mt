use 5.010;
use warnings;
use Benchmark qw( cmpthese timethese :hireswallclock );
use Config;
use UUID;
use Data::GUID 'guid' => { -as => 'dg_guid' };
use Data::UUID::LibUUID;
use Data::UUID::MT;
use Data::UUID;
use UUID::Tiny;
use List::AllUtils qw/max/;

my $ug1 = Data::UUID::MT->new( version => 1 );
my $next1 = $ug1->iterator;
my $ug4 = Data::UUID::MT->new( version => 4 );
my $next4 = $ug4->iterator;
my $ug4s = Data::UUID::MT->new( version => '4s' );
my $next4s = $ug4s->iterator;

my $duuid = Data::UUID->new;

say "Benchmark on $Config{archname} with $Config{uvsize} byte integers.\n";
print << "HERE";
Key:
  U     => UUID $UUID::VERSION
  UT    => UUID::Tiny $UUID::Tiny::VERSION
  DG    => Data::GUID $Data::GUID::VERSION
  DU    => Data::UUID $Data::UUID::VERSION
  DULU  => Data::UUID::LibUUID $Data::UUID::LibUUID::VERSION
  DUMT  => Data::UUID::MT $Data::UUID::MT::VERSION

Benchmarks are marked as to which UUID version is generated.
Some modules offer method ('meth') and func ('func') interfaces.

HERE
my $count = -2;
my $results = timethese( $count, {
    'U|v?'          => sub { UUID::generate(my $u) },
    'UT|v1'         => sub { create_UUID() },
    'UT|v4'         => sub { create_UUID(UUID_V4) },
    'DG|v1|meth'    => sub { Data::GUID->guid; },
    'DG|v1|func'    => sub { dg_guid(); },
    'DU|v1'         => sub { $duuid->create_bin() },
    'DULU|v1'       => sub { new_uuid_binary(1) },
    'DULU|v2'       => sub { new_uuid_binary(2) },
    'DULU|v4'       => sub { new_uuid_binary(4) },
    'DUMT|v1|meth'  => sub { $ug1->create },
    'DUMT|v1|func'  => sub { $next1->() },
    'DUMT|v4|meth'  => sub { $ug4->create },
    'DUMT|v4|func'  => sub { $next4->() },
    'DUMT|v4s|meth' => sub { $ug4s->create },
    'DUMT|v4s|func' => sub { $next4s->() },
  },  "none"
);

## Copied from Benchmark.pm
  # Flatten in to an array of arrays with the name as the first field
  my @vals = map{ [ $_, @{$results->{$_}} ] } keys %$results;

  for (@vals) {
    # The epsilon fudge here is to prevent div by 0.  Since clock
    # resolutions are much larger, it's below the noise floor.
    my $elapsed = do {
#      if ($style eq 'nop') {$_->[4]+$_->[5]}
#      elsif ($style eq 'noc') {$_->[2]+$_->[3]}
#      else {$_->[2]+$_->[3]+$_->[4]+$_->[5]}
      $_->[2]+$_->[3]+$_->[4]+$_->[5]
    };
    my $rate = $_->[6]/(($elapsed)+0.000000000000001);
    $_->[7] = $rate;
  }

  # Sort by rate
  @vals = sort { $a->[7] <=> $b->[7] } @vals;
## end copy

my $width = max map { length( $_->[0]) } @vals; 
my $format = "\%${width}s \%d/s\n";
printf($format, $_->[0], $_->[7]) for @vals;


