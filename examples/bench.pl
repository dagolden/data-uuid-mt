use 5.010;
use warnings;
use Benchmark qw( cmpthese :hireswallclock );
use Config;
use Data::UUID::LibUUID;
use Data::UUID::MT;
use Data::UUID;
use UUID::Tiny;

my $ug1 = Data::UUID::MT->new( version => 1 );
my $next1 = $ug1->iterator;
my $ug4 = Data::UUID::MT->new( version => 4 );
my $next4 = $ug4->iterator;
my $ug4s = Data::UUID::MT->new( version => '4s' );
my $next4s = $ug4s->iterator;

my $duuid = Data::UUID->new;

say "Benchmark on $Config{archname} with $Config{uvsize} byte integers.\n";
print << 'HERE';
Key:
  DU    => Data::UUID ('meth' => method, 'iter' => iterator)
  DULU  => Data::UUID::LibUUID
  DUMT  => Data::UUID::MT
  UT    => UUID::Tiny

HERE
my $count = -1;
cmpthese( $count, {
    'DUMT|v1|meth'  => sub { $ug1->create },
    'DUMT|v1|iter'  => sub { $next1->() },
    'DUMT|v4|meth'  => sub { $ug4->create },
    'DUMT|v4|iter'  => sub { $next4->() },
    'DUMT|v4s|meth' => sub { $ug4s->create },
    'DUMT|v4s|iter' => sub { $next4s->() },
    'DU|v1'         => sub { $duuid->create_bin() },
    'UT|v1'         => sub { create_UUID() },
    'UT|v4'         => sub { create_UUID(UUID_V4) },
    'DULU|v1'       => sub { new_uuid_binary(1) },
    'DULU|v2'       => sub { new_uuid_binary(2) },
    'DULU|v4'       => sub { new_uuid_binary(4) },
  }
);

