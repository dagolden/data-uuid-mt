use 5.010;
use strict;
use warnings;

package Data::UUID::MT;
# VERSION

use Config;
use Math::Random::MT::Auto;
use Time::HiRes;

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
    _prng => $prng,
    _version => $args{version},
  };
  
  bless $self, $class;

  $self->{_iterator} = $self->_build_iterator;

  return $self;
}

sub _build_iterator {
  my $self = shift;
  # get the iterator based on int size and UUID version
  my $int_size = $Config{uvsize};
  my $builder = $builders{$int_size}{$self->{_version}};
  return $self->$builder;
}

sub create {
  return shift->{_iterator}->();
}

sub create_hex {
  return uc join "-", unpack("H*", shift->{_iterator}->() );
}

sub create_string {
  return uc join "-", unpack("H8H4H4H4H12", shift->{_iterator}->());
}

sub iterator {
  return shift->{_iterator};
}

sub reseed {
  my $self = shift;
  $self->{_prng}->srand(@_ ? @_ : ());
}

#--------------------------------------------------------------------------#
# UUID algorithm closure generators
#--------------------------------------------------------------------------#

sub _build_64bit_v1 {
  my $self = shift;
  my $gregorian_offset = 12219292800 * 10_000_000;
  my $prng = $self->{_prng};

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
  my $prng = $self->{_prng};

  return sub {
    # Adapted from UUID::Tiny
    my $timestamp = Time::HiRes::time();

    # hi = time mod (1000000 / 0x100000000)
    my $hi = int( $timestamp / 65536.0 / 512 * 78125 );
    $timestamp -= $hi * 512.0 * 65536 / 78125;
    my $low = int( $timestamp * 10000000.0 + 0.5 );

    # MAGIC offset: 01B2-1DD2-13814000
    if ( $low < 0xec7ec000 ) {
        $low += 0x13814000;
    }
    else {
        $low -= 0xec7ec000;
        $hi++;
    }

    if ( $hi < 0x0e4de22e ) {
        $hi += 0x01b21dd2;
    }
    else {
        $hi -= 0x0e4de22e;    # wrap around
    }

    # UUID v1 shuffles the time bits around
    my $uuid  = pack( 'NnnNN',
      $low, $hi & 0xffff, ( $hi >> 16 ) & 0x0fff, $prng->irand, $prng->irand
    );
    vec($uuid, 87, 1) = 0x1;        # force MAC multicast bit on per RFC
    vec($uuid, 13, 4) = 0x1;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

sub _build_64bit_v4 {
  my $self = shift;
  my $prng = $self->{_prng};

  return sub {
    my $uuid = pack("Q>2", $prng->irand, $prng->irand);
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

sub _build_32bit_v4 {
  my $self = shift;
  my $prng = $self->{_prng};

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
  my $prng = $self->{_prng};

  return sub {
    my ($sec,$usec) = Time::HiRes::gettimeofday();
    my $uuid = pack("Q>2",
      $sec*10_000_000 + $usec*10, $prng->irand
    );
    # rotate last timestamp bits to make room for version field
    vec($uuid, 14, 4) = vec($uuid, 15, 4);
    vec($uuid, 15, 4) = vec($uuid, 12, 4);
    vec($uuid, 12, 4) = vec($uuid, 13, 4);
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

# "4s" is custom "random" with sequential override based on
# 100 nanosecond intervals since epoch
sub _build_32bit_v4s {
  my $self = shift;
  my $prng = $self->{_prng};

  return sub {
    # Adapted from UUID::Tiny
    my $timestamp = Time::HiRes::time();

    # hi = time mod (1000000 / 0x100000000)
    my $hi = int( $timestamp / 65536.0 / 512 * 78125 );
    $timestamp -= $hi * 512.0 * 65536 / 78125;
    my $low = int( $timestamp * 10000000.0 + 0.5 );

    # MAGIC offset: 01B2-1DD2-13814000
    if ( $low < 0xec7ec000 ) {
        $low += 0x13814000;
    }
    else {
        $low -= 0xec7ec000;
        $hi++;
    }

    if ( $hi < 0x0e4de22e ) {
        $hi += 0x01b21dd2;
    }
    else {
        $hi -= 0x0e4de22e;    # wrap around
    }

    my $uuid = pack("N4", $hi, $low, $prng->irand, $prng->irand);
    # rotate last timestamp bits to make room for version field
    vec($uuid, 14, 4) = vec($uuid, 15, 4);
    vec($uuid, 15, 4) = vec($uuid, 12, 4);
    vec($uuid, 12, 4) = vec($uuid, 13, 4);
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

1;

# ABSTRACT: Fast random UUID generator using the Mersenne Twister algorithm

=for Pod::Coverage method_names_here

=head1 SYNOPSIS

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
  
=head1 DESCRIPTION

This UUID generator uses the excellent L<Math::Random::MT::Auto> module
as a source of fast, high-quality (pseudo) random numbers.

Three different types of UUIDs are supported.  Two are consistent with
the official RFC and one is a custom variant that provides a 'sequential UUID'
that can be advantageous when used as a primary database key.

=head2 Version 1 UUIDs

The UUID generally follows the "version 1" spec from the UUID, however the
clock sequence and MAC address are randomly generated each time.  This is
permissible within the spec of the RFC.  The random MAC address has the
broadcast bit set as mandated to ensure it does not conflict with real MAC
addresses.  This is slower than other modules that generate "version 1" UUIDs
with the actual MAC address, but provides additional security by concealing the
source of UUIDs.

=head2 Version 4 UUIDs

The UUID follows the "version 4" spec, with 122 pseudo random bits and
6 mandated bits that define the "variant" and "version" fields.

=head2 Version 4s UUIDs

This is a custom UUID form that resembles "version 4" form, but that overlays
the first 60 bits with a timestamp akin to "version 1",  Unlike "verson 1",
this custom version preserves the ordering of bits from high to low, whereas
"version 1" puts the low 32 bits of the timestamp first, then the middle 16
bits, then multiplexes the high bits with version field.  This provides a
"sequential UUID" with the timestamp providing order and the remaining random
bits making collision with other UUIDs created at the exact same microsecond
unlikely.

=head2 Unsupported: Versions 2, 3 and 5

This modules focuses on random generation of UUID elements and does not
support UUID versions 2, 3 and 5.

=head1 COMPARISON TO OTHER UUID MODULES

XXX write something here -- maybe a table of modules and support

XXX benchmarking (maybe controversial)

=head1 SEE ALSO

=for :list
* L<RFC 4122 A Universally Unique IDentifier (UUID) URN Namespace|http://www.apps.ietf.org/rfc/rfc4122.html>

=cut

# vim: ts=2 sts=2 sw=2 et:
