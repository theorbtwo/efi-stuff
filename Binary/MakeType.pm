package Binary::MakeType;
# -*- cperl -*-
use strictures 1;
use autodie;
use feature 'state';
use feature 'postderef';
use feature 'say';
no warnings 'experimental';
use Try::Tiny;
use Carp 'longmess', 'shortmess', 'carp';
use Scalar::Util 'looks_like_number';
use Encode;

our $file_endian = 'le';

sub pad_to {
    my ($pad_to, $rel_start) = @_;
    sub {
        my ($infh) = @_;
        my $rel_pos = tell($infh) - $rel_start;
        say "padding to $pad_to from rel_pos $rel_pos";
        if ($rel_pos % $pad_to) {
            my $pad_len = $pad_to - ($rel_pos % $pad_to);
            say "padding by $pad_len";
            my $pad_val = make_counted_string(sub {$pad_len})->(@_);
            return $pad_val;
        } else {
            return '';
        }
    };
}

sub make_until_end {
    my ($type) = @_;
    sub {
        my ($fh) = @_;
        my @ret;
        while (not eof $fh) {
            my $pos = tell($fh);
            #print "($pos)\n";
            my $val = $type->($fh);
            my $bail_out;
            try {
                $val = $type->($fh);
            } catch {
                push @ret, "ERROR reading: $_ at ".longmess();
                $bail_out = 1;
            };
            last if $bail_out;
            last if $val eq '__last__';
            push @ret, $val;
            if ($pos == tell($fh)) {
                die "Infinite loop in make_until_end: pos $pos before and after read";
            }
        }
        return \@ret;
    }
}

sub make_encoded_string {
  my ($encoding) = @_;
  my $enc_len;
  if ($encoding =~ m/utf(\d+)/) {
    $enc_len = $1/8;
  } elsif ($encoding eq 'ascii') {
    $enc_len = 1;
  } else {
    die "Don't know how large an element of encoding $encoding is";
  }
  my $term = "\0" x ($enc_len);

  sub {
      my ($fh) = @_;
      my $ret = '';
      my $raw = '';
      
      while (1) {
          # Is this an error, or not?  I'm leaning toward not...
          last if eof $fh;
          my $e = read_len($fh, $enc_len);
          if ($e eq $term) {
              last;
          }
          $raw .= $e;
      }
      return decode($encoding, $raw);
  }
}

sub make_bitmask {
  my ($raw_type, $values) = @_;
  sub {
    my $raw = $raw_type->(@_);
    my $raw_remainder = $raw;
    my $ret = {_raw => $raw, '_raw=x' => sprintf "0x%x", $raw};
    for my $mask (keys %$values) {
      if ($raw & $mask) {
        $raw_remainder = $raw_remainder & ~$mask;
        $ret->{$values->{$mask}} = ($raw & $mask);
      }
    }
    $ret->{'_raw_remainder'} = $raw_remainder;
    $ret->{'_raw_remainder=x'} = sprintf("0x%x", $raw_remainder);
    return $ret;
  }
}

sub make_enum {
  my ($raw_type, $values) = @_;
  if (ref $values eq 'ARRAY') {
    my $values_hash = {};
    for my $i (0..$#{$values}) {
      $values_hash->{$i} = $values->[$i];
    }
    $values = $values_hash;
  }
  sub {
    my $raw = $raw_type->(@_);
    if (exists $values->{$raw}) {
      return $values->{$raw};
    } else {
      if (looks_like_number $raw) {
        return sprintf("Don't know enum for 0x%x = %d\n", $raw, $raw);
      } else {
        return sprintf("Don't know enum for %s\n", $raw);
      }
    }
  }
}

sub make_tagged_struct {
  my ($tag_type, $tags) = @_;
  sub {
    my $tag = $tag_type->(@_);
    my $inner_type = $tags->{$tag};
    if (!$inner_type) {
      die "Don't know how to handle tag $tag";
    }
    my $ret = $inner_type->(@_);
    if (ref $ret eq 'HASH') {
      $ret->{tag} = $tag;
    } else {
      $ret = { tag => $tag,
               data => $ret };
    }
    return $ret;
  }
}

sub make_counted_array {
  my ($count_type, $element_type) = @_;
  sub {
    my (@args) = @_;
    my $count = $count_type->(@args);
    my $ret = [];
    for my $i (0..$count-1) {
      my $bail_out;
      if (eof $args[0]) {
        $ret->[$i] = "At end of file reading element $i of counted array at ".longmess();
        last;
      }
      try {
        $ret->[$i] = $element_type->(@args);
      } catch {
        $ret->[$i] = "ERROR reading element $i of counted array: $_ at ".longmess();
        $bail_out = 1;
      };
      last if $bail_out;
    }
    return $ret;
  }
}

sub make_counted_string {
  my ($count_type) = @_;
  sub {
    my ($fh) = @_;
    my $len = $count_type->(@_);
    my $string = read_len($fh, $len);
    return $string;
  }
}

sub make_numeric {
  my ($desc) = @_;
  my $endian = $file_endian;
  $desc =~ s/(le|be)// and $endian=$1;

  my $signed = 'u';
  $desc =~ s/([usf])// and $signed=$1;

  my $bits;
  $desc =~ s/(\d+)// and $bits=$1;
  
  if ($desc) {
    die "Don't know what to do with description part '$desc'";
  }
  $endian //= $file_endian;
  $signed //= 's';
  if (!$bits) {
    die "Bits is a required part of a numeric desc";
  }

  my $canon_desc = "$endian$bits$signed";
  state $known_packs = {
                        'le64f' => 'd<',
                        'le64u' => 'Q<',
                        'le64s' => 'q<',

                        'le32u' => 'L<',
                        'le32s' => 'l<',
                        'le32f' => 'f<',

                        'le16s' => 's<',
                        'le16u' => 'S<',

                        'le8s' => 'c',
                        'le8u' => 'C',


                        'be64f' => 'd>',
                        'be64u' => 'Q>',
                        'be64s' => 'q>',

                        'be32u' => 'L>',
                        'be32s' => 'l>',
                        'be32f' => 'f>',

                        'be16s' => 's>',
                        'be16u' => 'S>',

                        'be8s' => 'c',
                        'be8u' => 'C',

                       };

  if (!exists $known_packs->{$canon_desc}) {
    die "Don't know how to unpack a numeric $canon_desc";
  }

  my $pack_pattern = $known_packs->{$canon_desc};
  my $bytelen = $bits / 8;

  sub {
    unpack($pack_pattern, read_len($_[0], $bytelen));
  }
}

sub make_struct_array {
  my ($array) = @_;
  sub {
    my $ret={};
    my $i=0;
    my $start_pos = tell($_[0]);

    while ($i <= $#$array) {
      my $rel_pos = tell($_[0]) - $start_pos;
      my $name = $array->[$i++];
      my $type = $array->[$i++];
      printf "rel_pos = 0x%x, i=%d, name=%s\n", $rel_pos, $i, $name;

      my $bail_out=0;
      my $val;
      my @outer_args = @_;
      try {
        $val = $type->(@outer_args);
      } catch {
        $val = "ERROR reading $name: $_ at ".longmess();
        $bail_out = 1;
      };

      printf "rel_pos = 0x%x, i=%d, name=%s, val='%s'\n", $rel_pos, $i, $name, $val;
      
      $ret->{$name} = $val;
      $ret->{"$i=$name"} = $val;
      if (looks_like_number $val) {
        $ret->{"$i=$name=x"} = sprintf("0x%x", $val);
      }
      
      last if $bail_out;
    }
    return $ret;
  }
}

sub make_constant_string {
  my ($const) = @_;
  my $len = length($const);
  sub {
    my $got = read_len($_[0], $len);
    if ($const ne $got) {
      die "Required constant string failed, got '$got', expected '$const'";
    }
    # Micro-optimization: return $const, which can be shared, rather then $got, which can't be.
    return $const;
  }
}

sub read_len {
  my ($fh, $len) = @_;
  if (not defined $len) {
    carp "Undefined len in read_len!";
  }
  if ($len == 0) {
    # $/=\0 is a depreciated form of slurp ($/=undef), not read zero bytes, which comes up in counted strings.
    return '';
  }
  local $/=\$len;
  my $ret = <$fh>;
  if (not defined $ret) {
    if (eof $fh) {
      die "Tried to read past end of file?";
      return '';
    }
    die "Read failed: $!";
  }
  return $ret;
}
