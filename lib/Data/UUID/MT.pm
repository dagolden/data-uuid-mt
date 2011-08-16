use 5.010;
use strict;
use warnings;

package Data::UUID::MT;
# VERSION

use Config;
use Math::Random::MT::Auto;
use Scalar::Util 1.10 ();
use Time::HiRes ();

# track objects across threads for reseeding
my ($can_weaken, @objects);
$can_weaken = Scalar::Util->can('weaken');
sub CLONE { defined($_) && $_->reseed for @objects }

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

  if ($can_weaken) {
    push @objects, $self;
    Scalar::Util::weaken($objects[-1]);
  }

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
  return "0x" . unpack("H*", shift->{_iterator}->() );
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
  my $pid = $$;

  return sub {
    if ($$ != $pid) {
      $prng->reseed();
      $pid = $pid;
    }
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
  my $pid = $$;

  return sub {
    if ($$ != $pid) {
      $prng->reseed();
      $pid = $pid;
    }
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
  my $pid = $$;

  return sub {
    if ($$ != $pid) {
      $prng->reseed();
      $pid = $pid;
    }
    my $uuid = pack("Q>2", $prng->irand, $prng->irand);
    vec($uuid, 13, 4) = 0x4;        # set UUID version
    vec($uuid, 35, 2) = 0x2;        # set UUID variant
    return $uuid;
  }
}

sub _build_32bit_v4 {
  my $self = shift;
  my $prng = $self->{_prng};
  my $pid = $$;

  return sub {
    if ($$ != $pid) {
      $prng->reseed();
      $pid = $pid;
    }
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
  my $pid = $$;

  return sub {
    if ($$ != $pid) {
      $prng->reseed();
      $pid = $pid;
    }
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
  my $pid = $$;

  return sub {
    if ($$ != $pid) {
      $prng->reseed();
      $pid = $pid;
    }
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
  my $uuid2 = $ug->create_hex();    # 0xB0470602A64B11DA863293EBF1C0E05A
  my $uuid3 = $ug->create_string(); # B0470602-A64B-11DA-8632-93EBF1C0E05A

  # iterator -- avoids some method call overhead
  my $next = $ug->iterator;
  my $uuid4 = $next->();

=head1 DESCRIPTION

This UUID generator uses the excellent L<Math::Random::MT::Auto> module
as a source of fast, high-quality (pseudo) random numbers.

Three different types of UUIDs are supported.  Two are consistent with
RFC 4122 and one is a custom variant that provides a 'sequential UUID'
that can be advantageous when used as a primary database key.

=head2 Version 1 UUIDs

The UUID generally follows the "version 1" spec from the RFC, however the
clock sequence and MAC address are randomly generated each time.  (This is
permissible within the spec of the RFC.)  The random "MAC address" portion of
the UUID has the multicast bit set as mandated by the RFC to ensure it does not
conflict with real MAC addresses.  This UUID has 60 bits of timestamp data and
61 bits of pseudo-random data and 7 mandated bits (multicast bit, "variant"
field and "version" field).

=head2 Version 4 UUIDs

The UUID follows the "version 4" spec, with 122 pseudo-random bits and
6 mandated bits ("variant" field and "version" field).

=head2 Version 4s UUIDs

This is a custom UUID form that resembles "version 4" form, but that overlays
the first 60 bits with a timestamp akin to "version 1",  Unlike "version 1",
this custom version preserves the ordering of bits from high to low, whereas
"version 1" puts the low 32 bits of the timestamp first, then the middle 16
bits, then multiplexes the high bits with version field.  This provides a
"sequential UUID" with the timestamp providing order and the remaining random
bits making collision with other UUIDs created at the exact same microsecond
unlikely.  This UUID has 60 timestamp bits, 62 pseudo-random bits and 6
mandated bits ("variant" field and "version" field).

=head2 Unsupported: Versions 2, 3 and 5

This module focuses on generation of UUIDs with random elements and does not
support UUID versions 2, 3 and 5.

=attr new

  my $ug = Data::UUID::MT->new( version => 4 );

Creates a UUID generator object.  The only allowed versions are
"1", "4" and "4s".  If no version is specified, it defaults to "4".

=attr create

  my $uuid = $ug->create;

Returns a UUID packed into a 16 byte string.

=attr create_hex

  my $uuid = $ug->create_hex(); # 0xB0470602A64B11DA863293EBF1C0E05A

Returns a UUID as a hex string, prefixed with "0x".

=attr create_string

  my $uuid = $ug->create_string(); #

Returns UUID as an uppercase string in "standard" format, e.g.
C<B0470602-A64B-11DA-8632-93EBF1C0E05A>

=attr iterator

  my $next = $ug->iterator;
  my $uuid = $next->();

Returns a reference to the internal UUID generator function.  Because this
avoids method call overhead, it is slightly faster than calling C<create>.

=attr reseed

  $ug->reseed;

Reseeds the internal pseudo-random number generators.  This happens
automatically after a fork or thread creation (assuming Scalar::Util::weaken).

Any arguments provided are passed to Math::Random::MT::Auto::srand() for
custom seeding, if desired.

  $ug->reseed('hotbits' => 250, '/dev/random');

=head1 COMPARISON TO OTHER UUID MODULES

At the time of writing, there are five other general purpose UUID generators
on CPAN.  Data::GUID::MT is included in the dicussion below for comparison.

=for :list:
* L<Data::GUID> - version 1 UUIDs (wrapper around Data::UUID)
* L<Data::UUID> - version 1 or 3 UUIDs (derived from RFC 4122 code)
* L<Data::UUID::LibUUID> - version 1 or 4 UUIDs (libuuid)
* L<UUID> - version 1 or 4 UUIDs (libuuid)
* L<UUID::Tiny> - versions 1, 3, 4, or 5 (pure perl)
* L<Data::GUID::MT> - version 1 or 4 (or custom sequential "4s")

C<libuuid> based UUIDs may generally be either version 4 (preferred) or version
1 (fallback), depending on the availability of a good random bit source (e.g.
/dev/random).  C<libuuid> version 1 UUIDs could also be provided by the
C<uuidd> daemon if available.

UUID.pm leaves the choice of version up to C<libuuid>.  Data::UUID::LibUUID
does so by default, but also allows specifying a specific version.  Note that
Data::UUID::LibUUID incorrectly refers to version 1 UUIDs as version 2 UUIDs.
For example, to get a version 1 UUID explicitly, you must call
C<Dat::UUID::LibUUID::new_uuid_binary(2)>.

In addition to sections below, there are additional slight difference in how
modules/libraries treat the "clock sequence" field and otherwise attempt to
keep state between calls, but this is generally immaterial.

=head2 Version 1 UUIDs and Ethernet MAC addresses

Version 1 UUID generators differ in whether they include the Ethernet MAC
address as a "node identifier" as specified in RFC 4122.  Including the MAC
has security implications as Version 1 UUIDs can then be traced to a
particular machine at a particular time.

For C<libuuid> based modules, Version 1 UUIDs will include the actual MAC
address, if available, or will substitute a random MAC (with multicast bit
set).

Data::UUID version 1 UUIDs do not contain the MAC address, but replace
it with an MD5 hash of data including the hostname and hostid (possibly
just the IP address), modified with the multicast bit.

Both UUID::Tiny and Data::UUID::MT version 1 UUIDs do not contain the actual
MAC address, but replace it with a random multicast MAC address.

=head2 Source of random bits

All the modules differ in the source of random bits.

C<libuuid> based modules get random bits from C</dev/random> or C</dev/urandom>
or fall back to a pseudo-random number generator.

Data::UUID only uses random data to see the clock sequence and gets bits from
the C C<rand()> function.

UUID::Tiny uses Perl's C<rand()> function.

Data::UUID::MT gets random bits from L<Math::Random::MT::Auto>, which uses the
Mersenne Twister algorithm.  Math::Random::MT::Auto seeds from system sources
(including Win32 specific ones on that platform) if available and falls back to
other less ideal sources if not.

=head2 Fork and thread safety

Pseudo-random number generators used in generating UUIDs should be reseeded if
the process forks or if threads are created.

Data::UUID::MT checks if the process ID has changed before generating a UUID
and reseeds if necessary.  If L<Scalar::Util> is installed and provides
C<weaken()>, Data::UUID::MT will also reseed its objects on thread creation.

Data::UUID::LibUUID will reseed on fork on Mac OSX.

I have not explored further whether other UUID generators are fork/thread safe.

=head2 Benchmarks

The F<examples/bench.pl> program included with this module does some simple
benchmarking of UUID generation speeds.  Here is the output from my desktop
system (AMD Phenom II X6 1045T CPU).  Note that "v?" is used where the choice
is left to C<libuuid> -- which will result in version 4 UUIDs on my system.

 Benchmark on Perl v5.14.0 for x86_64-linux with 8 byte integers.

 Key:
   U     => UUID 0.02
   UT    => UUID::Tiny 1.03
   DG    => Data::GUID 0.046
   DU    => Data::UUID 1.217
   DULU  => Data::UUID::LibUUID 0.05
   DUMT  => Data::UUID::MT 0.001

 Benchmarks are marked as to which UUID version is generated.
 Some modules offer method ('meth') and func ('func') interfaces.

         UT|v1 92914/s
         UT|v4 114989/s
       DULU|v1 176127/s
       DULU|v? 178006/s
 DUMT|v4s|meth 275687/s
  DUMT|v1|meth 291445/s
       DULU|v4 292322/s
          U|v? 300744/s
 DUMT|v4s|func 309688/s
  DUMT|v1|func 330830/s
    DG|v1|func 340786/s
    DG|v1|meth 380074/s
  DUMT|v4|meth 502750/s
  DUMT|v4|func 598529/s
         DU|v1 1263170/s


=head1 SEE ALSO

=for :list
* L<RFC 4122 A Universally Unique IDentifier (UUID) URN Namespace|http://www.apps.ietf.org/rfc/rfc4122.html>

=cut

# vim: ts=2 sts=2 sw=2 et:
