use 5.010;
use strict;
use warnings;

package Data::UUID::MT;
# VERSION

# Dependencies
use autodie 2.00;
use Math::Random::MT::Auto;
use Time::HiRes;
use Config;

# XXX need Math::BigInt on 32 bit systems
use if $Config{uvsize} != 8 => 'Math::BigInt';

# XXX for testing
use Math::BigInt;

# XXX should we automatically check $$ to reseed?  Or have CLONE (and track?)

# HoH: $builders{$Config{uvsize}}{$version}
my %builders = (
  '8' => {
    '1'   =>  '_build_64bit_v1',
    '4'   =>  '_build_64bit_v4',
    '4s'  =>  '_build_64bit_v4s',
  },
  '4' => {
    '1'   =>  '_build_32bit_v1',
    '4'   =>  '_build_32bit_v4',
    '4s'  =>  '_build_32bit_v4s',
  }
);

sub new {
  my ($class, %args) = @_;
  $args{version} //= 4;
  Carp::croak "Unsupported UUID version '$args{version}'"
    unless $args{version} =~ /^(?:1|4|4s)$/;
  my $int_size = $Config{uvsize};
  Carp::croak "Unsupported integer size '$int_size'"
    unless $int_size == 4 || $int_size == 8;

  my $prng = Math::Random::MT::Auto->new;

  my $self = {
    prng => $prng,
    version => $args{version},
  };
  
  bless $self, $class;

  $self->{iterator} = $self->_build_iterator;

  return $self;
}

sub _build_iterator {
  my $self = shift;
  # get the iterator based on int size and UUID version
  my $int_size = 4; # XXX $Config{uvsize};
  my $builder = $builders{$int_size}{$self->{version}};
  return $self->$builder;
}

sub create {
  return shift->{iterator}->();
}

sub create_hex {
  return uc join "-", unpack("H*", shift->{iterator}->() );
}

sub create_string {
  return uc join "-", unpack("H8H4H4H4H12", shift->{iterator}->());
}

sub iterator {
  return shift->{iterator};
}

sub reseed {
  my $self = shift;
  $self->{prng}->srand(@_ ? @_ : ());
}

sub version {
  return shift->{version};
}

#--------------------------------------------------------------------------#
# UUID algorithm closure generators
#--------------------------------------------------------------------------#

sub _build_64bit_v1 {
  my $self = shift;
  my $gregorian_offset = 12219292800 * 10_000_000;
  my $prng = $self->{prng};

  return sub {
    my ($sec,$usec) = Time::HiRes::gettimeofday();
    my $raw_time = pack("Q>", $sec*10_000_000 + $usec*10 + $gregorian_offset);
    # UUID v1 shuffles the time bits around
    my $uuid  = substr($raw_time,4,4)
              . substr($raw_time,2,2)
              . substr($raw_time,0,2)
              . pack("Q>", $prng->irand);
    vec($uuid, 87, 1) = 0x1;        # force MAC multicast bit on per RFC
    vec($uuid, 13, 4) = 0x1;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

sub _build_32bit_v1 {
  my $self = shift;
  my $gregorian_offset = Math::BigInt->new("12219292800")->bmul(10_000_000);
  my $prng = $self->{prng};

  return sub {
    my ($sec,$usec) = Time::HiRes::gettimeofday();
    my $timestamp = Math::BigInt->new($sec);
    $timestamp->bmul(10_000_000)->badd($usec*10)->badd($gregorian_offset);
    # pack it up as 64 bit
    my $j = $timestamp->copy->brsft(32);
    my $k = $timestamp - $j->copy->blsft(32);
    my $raw_time = pack("NN", $j, $k);
    # UUID v1 shuffles the time bits around
    my $uuid  = substr($raw_time,4,4)
              . substr($raw_time,2,2)
              . substr($raw_time,0,2)
              . pack("NN", $prng->irand, $prng->irand);
    vec($uuid, 87, 1) = 0x1;        # force MAC multicast bit on per RFC
    vec($uuid, 13, 4) = 0x1;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

sub _build_64bit_v4 {
  my $self = shift;
  my $prng = $self->{prng};

  return sub {
    my $uuid = pack("Q>2", $prng->irand, $prng->irand);
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

sub _build_32bit_v4 {
  my $self = shift;
  my $prng = $self->{prng};

  return sub {
    my $uuid = pack("N4",
      $prng->irand, $prng->irand, $prng->irand, $prng->irand
    );
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

# "4s" is custom "random" with sequential override based on
# 100 nanosecond intervals since epoch
sub _build_64bit_v4s {
  my $self = shift;
  my $prng = $self->{prng};

  return sub {
    my ($sec,$usec) = Time::HiRes::gettimeofday();
    my $uuid = pack("Q>2",
      $sec*10_000_000 + $usec*10, $prng->irand
    );
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

# "4s" is custom "random" with sequential override based on
# 100 nanosecond intervals since epoch
sub _build_32bit_v4s {
  my $self = shift;
  my $prng = $self->{prng};

  return sub {
    my ($sec,$usec) = Time::HiRes::gettimeofday();
    my $timestamp = Math::BigInt->new($sec);
    $timestamp->bmul(10_000_000)->badd($usec*10);
    # pack it up as 128 bit
    my $j = $timestamp->copy->brsft(32);
    my $k = $timestamp - $j->copy->blsft(32);
    my $uuid = pack("N4", $j, $k, $prng->irand, $prng->irand);
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

1;

# ABSTRACT: Fast random UUID generator using the Mersenne Twister algorithm

=for Pod::Coverage method_names_here

=begin wikidoc

= SYNOPSIS

  use Data::UUID::MT;
  my $ug1 = Data::UUID::MT->new( version => 4 ); # "1", "4" or "4s"
  my $ug2 = Data::UUID::MT->new();               # default is "4"

  # method interface
  my $uuid1 = $ug->create();        # 16 byte binary string
  my $uuid2 = $ug->create_hex();    # B0470602-A64B-11DA-8632-93EBF1C0E05A
  my $uuid3 = $ug->create_string(); # 0xB0470602A64B11DA863293EBF1C0E05A

  # iterator -- avoids some method call overhead
  my $next = $ug->iterator;
  my $uuid4 = $next->();

  # after fork or thread creation
  $ug->reseed;
  
= DESCRIPTION

This module might be cool, but you'd never know it from the lack
of documentation.

= USAGE

Good luck!

= SEE ALSO

Maybe other modules do related things.

=end wikidoc

=cut

# vim: ts=2 sts=2 sw=2 et:
