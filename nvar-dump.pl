#!/usr/bin/perl
use strictures 2;
use Binary::MakeType;
use feature 'say';
use UEFI;
use Data::Printer colored => 1, output => 'stdout', return_value => 'pass';
$|=1;

# This will attempt to dump an "NVAR" style EFI variable store out, in
# an appoximation of the format that you'd see under
# /sys/firmware/efi/vars/ on a linux system.

my $uint8  = $UEFI::uint8;
my $uint16 = $UEFI::uint16;
my $uint24 = $UEFI::uint24;
my $uint32 = $UEFI::uint32;
my $uint64 = $UEFI::uint64;

my $guid = $UEFI::guid;
my $type_device_path = $UEFI::type_device_path;

my $infn = shift;
if (!$infn or !-e $infn) {
    say STDERR "First argument should be a filename containing a dump of the 'NVAR' section of your flash chip.";
    say STDERR "This may be in a {cef5b9a3-476d-497f-9fdc-e98143e0422c} file";
}

open my $infh, "<", $infn or die "Can't open $infn: $!";

while (1) {
  # AMI-style EFI variables.
  my $var_header_start = tell($infh);
  #last if ($var_header_start >= $file_header_start + $file_header->{Size});
  #say "offset within file: ", $var_header_start - $file_header_start;
  #say "file size: ", $file_header->{Size};
  my $var_header = Binary::MakeType::make_struct_array([
                                                        magic => Binary::MakeType::make_constant_string('NVAR'),
                                                        size => $uint16,
                                                        next => $uint24,
                                                        attributes => Binary::MakeType::make_bitmask($uint8,
                                                                                                     {
                                                                                                      1 => 'runtime_access',
                                                                                                      2 => 'desc_ascii',
                                                                                                      4 => 'guid',
                                                                                                      8 => 'data',
                                                                                                      0x10 => 'exthdr',
                                                                                                      0x40 => 'authwr',
                                                                                                      0x20 => 'hardware_error_record',
                                                                                                      0x80 => 'valid',
                                                                                                     }),
                                                        # GUID, if attributes guid.
                                                        # GUID index, if !attributes guid.
                                                       ])->($infh);
    
  # https://github.com/chipsec/chipsec/blob/master/source/tool/chipsec/hal/uefi_platform.py
  if (!$var_header->{size}) {
    say "Bollocks, didn't get expected magic";
    system('hd', -s => $var_header_start - 0x20, $infn);
    last;
  }
  if ($var_header->{attributes}{guid}) {
    $var_header->{guid} = $guid->($infh);
  } else {
    my $guid_index  = $uint8->($infh);
    $var_header->{guid} = "FIXME, index=$guid_index";
    my $saved_pos = tell($infh);
    my $computed_pos = -16*($guid_index+1);
    # Seek to the EOF + $computed_pos (which is neg).
    seek($infh, $computed_pos, 2);
    $var_header->{guid} = $guid->($infh);
    seek($infh, $saved_pos, 0);
  }
  if ($var_header->{attributes}{desc_ascii}) {
    $var_header->{desc} = Binary::MakeType::make_encoded_string('utf8')->($infh);
  }
  my $expected_pos = $var_header_start + $var_header->{size};
  my $current_pos = tell($infh);
  my $offset = $expected_pos - $current_pos;
  $var_header->{data_len} = $offset;
  $var_header->{data} = Binary::MakeType::make_counted_string(sub {$offset})->($infh);


  # Known variables are listed in UEFI spec version 2.4 section 3.2.
  print "UEFI variable: ";
  print $var_header->{desc}
    if (defined $var_header->{desc});
  print ": ";
  print $var_header->{guid};
  print ": ";
  print $var_header->{data};
  print "\n";
  #$variables->{$var_header->{desc} || $var_header->{guid}} = $var_header->{data};

  if (not defined $var_header->{desc}) {
    # nop
  } elsif ($var_header->{desc} eq 'MonotonicCounter') {
    # This isn't listed in uefi spec sec 3.2, but is presumably used to implement the GetNextMonotonicCount() function of section 7.5.2.
  } elsif ($var_header->{desc} eq 'Timeout') {
    printf " Boot keyboard selection timeout: %d seconds\n", unpack 's', $var_header->{data};
  } elsif ($var_header->{desc} eq 'Lang') {
    printf " Language: %s\n", $var_header->{data};
  } elsif (grep {$var_header->{desc} eq $_} qw<ConOut ConIn ErrOut ConInDev ConOutDev ErrOutDev>) {
    open my $memfh, '<', \$var_header->{data};
    print $type_device_path->($memfh);
  } elsif ($var_header->{desc} =~ m/^Boot([0-9A-Fa-f]{4})$/) {
    # Contains an EFI_LOAD_OPTION, defined in section 3.1.3 of the main uefi spec.
    open my $loadoption_fh, '<', \$var_header->{data};
    my $loadoption_struct = Binary::MakeType::make_struct_array([
                                                                 Attributes => $uint32,
                                                                 FilePathListLength => $uint16,
                                                                 Description => Binary::MakeType::make_encoded_string('utf16le'),
                                                                ]);
    print "EFI_LOAD_OPTION\n";
    my $option = $loadoption_struct->($loadoption_fh);
    my $fpl_start = tell($loadoption_fh);
    while (1) {
      my $relpos = tell($loadoption_fh) - $fpl_start;
      say "Rel. pos within FilePathList: $relpos";
      say "Total length of FilePathList: ", $option->{FilePathListLength};
      last if ($relpos >= $option->{FilePathListLength});
      push @{$option->{FilePathList}}, $type_device_path->($loadoption_fh);
      p $option;
    }

    # ...and then the OptionalData, which is passed on to the image as an argument.
    p $option;
    # FilePathList => $type_device_path, # A device path, as above.
    # OptionalData => $uint32, # passed as arguments to the file?
  } elsif ($var_header->{desc} eq 'BootOrder') {
    # array of uint16, order of Boot#### elements.
  } else {
    say "Not a well-known type";
  }
  # if ($expected_pos != $current_pos) {
  #   say "Expected position of next header: $expected_pos, current pos: $current_pos, offset: $offset";
  #   seek ($infh, $expected_pos, 0);
  # }
  p $var_header;
}

