#!/usr/bin/perl
# -*- cperl -*-
use strictures 1;
use 5.12.0;
use lib '/mnt/shared/projects/games/talos/lib/';
use Binary::MakeType;
use Data::Printer colored => 1, output => 'stdout', return_value => 'pass';
use Scalar::Util 'looks_like_number';
use Encode 'decode';
use File::Path 'make_path';
use Path::Class;
$|=1;

# find -name body|grep -v 'DXE dependency'|grep -v 'User interface'|grep -v 'PE32 image'|grep -v 'Compressed section/body'|grep -v 'dependency section'|xargs -d"\n" file|grep -v 'JPEG'|grep -v 'PC bitmap'|grep -v 'GIF image'|less|perl -nE 'my $n=tr!/!/!; print "$_" if $n>2'|grep -v 'MS Windows'|cut -f1 -d:
#   ./3 9BD5C81D-096C-4625-A08B-405F78FE0CFC/0 Compressed section/0 Raw section/body
#     -- lha + header file, extra executable section for RAID controller
#   ./47 A08276EC-A0FE-4E06-8670-385336C7D093/0 Raw section/body
#   ./59 9FE7DE69-0AEA-470A-B50A-139813700813/0 Compressed section/0 Raw section/body
#     -- trust chain?
#   ./60 FBF95065-427F-47B3-8077-D13C60710998/0 Compressed section/0 Raw section/body
#     -- trust chain?
#   ./16 AmiBoardInfo/1 Compressed section/1 E6F4F8F7-4992-47B2-8302-8508745E4A23/body
#     -- $PIR PCI interrupt routing table. -- https://web.archive.org/web/19981206184517/http://microsoft.com/hwdev/busbios/PCIIRQ.HTM
#     -- $XLT ???
#     -- $APD ???
#   ./64 69009842-63F2-43DB-964B-EFAD1C39EC85/0 Raw section/body
#     -- just a bunch of FF.
#   ./9 DAC2B117-B5FB-4964-A312-0DCC77061B9B/0 Compressed section/0 97E409E6-4CC1-11D9-81F6-000000000000/body
#     -- ??? -- lots of repitition, raw image file?
#     -- After opening in the gimp, no, but there is a strong 33-byte pattern?
#   ./88 AMITSE/0 Compressed section/1 97E409E6-4CC1-11D9-81F6-000000000000/body
#     -- translations, english, general UI bits?
#   ./88 AMITSE/0 Compressed section/2 FE612B72-203C-47B1-8560-A66D946EB371/body
#     -- $SPF signature
#     -- includes names of many efi variables as utf16le strings!
#   ./10 9221315B-30BB-46B5-813E-1B1BF4712BD3/0 Compressed section/0 Raw section/body
#     -- nvar variables
#   ./11 CORE_DXE/0 Compressed section/1 97E409E6-4CC1-11D9-81F6-000000000000/body
#     -- translations, english, names of boot options?
#   ./74 D2596F82-F0E1-49FA-95BC-62012C795728/0 Compressed section/0 Raw section/body
#     -- ???
#   ./69 DAF4BF89-CE71-4917-B522-C89D32FBC59F/0 Compressed section/0 AB56DC60-0057-11DA-A8DB-000102EEE626/body
#     -- DMI info -- note, doesn't match reality for this motherboard, but does match what dmidecode gives.
#   ./46 CSMCORE/1 Compressed section/1 Raw section/body
#     -- legacy rom?  Includes many strings, IFE$ signature (?), $PnP signature ...?
#   ./58 9FE7DE69-0AEA-470A-B50A-139813680324/0 Compressed section/0 Raw section/body
#     -- another set of keys?
#   ./83 AmiTcgPlatformDxe/1 Compressed section/1 97E409E6-4CC1-11D9-81F6-000000000000/body
#     -- More english translations.  TPM
#   ./65 996AA1E0-1E8C-4F36-B519-A170A206FC14/0 Raw section/body
#     -- Just FF.
#   ./84 0AA31BC6-3379-41E8-825A-53F82CC0F254/0 Compressed section/0 Raw section/body
#     -- CDCD header?
#   ./85 142204E2-C7B1-4AF9-A729-923758D96D03/0 Compressed section/0 Raw section/body
#     -- INT 19 handler?
#   ./6 PostMsg/1 Compressed section/1 97E409E6-4CC1-11D9-81F6-000000000000/body
#     -- translation, english, "all settings were reset", etc.
#   ./61 9D7A05E9-F740-44C3-858B-75586A8F9C8E/0 Compressed section/0 Raw section/body
#     -- keys, again
#   ./86 7D113AA9-6280-48C6-BACE-DFE7668E8307/0 Compressed section/0 Raw section/body
#     -- Remarkably string-free, but has 0xAA55 signature.
#   ./13 ReFlash/1 Compressed section/1 97E409E6-4CC1-11D9-81F6-000000000000/body
#     -- Translations again, firmware upgrade
#   ./89 A59A0056-3341-44B5-9C9C-6D76F7673817/0 2EBE0275-6458-4AF9-91ED-D3F4EDB100AA/body
#     -- $SGN$ and $LGO$, AMI copyright messages.

my $variables;

my $infn = $ARGV[0];
open my $infh, '<', $infn or die "Can't open $infn: $!";
my $rom;
{
  local $/=undef;
  $rom = <$infh>;
}

my $byte = Binary::MakeType::make_numeric('le8u');
my $word = Binary::MakeType::make_numeric('le16u');
my $dword = Binary::MakeType::make_numeric('le32u');
my $dword_unix_time = sub {
  my $raw = $dword->(@_);
  scalar localtime $raw;
};

my $image_file_header = Binary::MakeType::make_struct_array([
                                                             Machine => Binary::MakeType::make_enum($word,
                                                                                                    {
                                                                                                     0x014c => 'i386',
                                                                                                     0x0200 => 'ia64',
                                                                                                     0x8664 => 'x64',
                                                                                                    }),
                                                             NumberOfSections => $word,
                                                             TimeDateStamp => $dword_unix_time,
                                                             PointerToSymbolsTable => $dword,
                                                             NumberOfSymbols => $dword,
                                                             SizeOfOptionalHeader => $word,
                                                             Characteristics => Binary::MakeType::make_bitmask($word,
                                                                                                               {
                                                                                                                2 => 'executable',
                                                                                                                0x100 => '32bit',
                                                                                                                0x2000 => 'dll',
                                                                                                               }),
                                                            ]);

my $prev_end = 0;

my $uint8  = Binary::MakeType::make_numeric('u8le');
my $uint16 = Binary::MakeType::make_numeric('u16le');
my $uint24 = sub {
  my ($infh) = @_;
  my ($a, $b, $c) = @{Binary::MakeType::make_counted_array(sub {3}, $uint8)->($infh)};
  ($c<<16) | ($b<<8) | $a;
};
my $uint32 = Binary::MakeType::make_numeric('u32le');
my $uint64 = Binary::MakeType::make_numeric('u64le');

my $guid = sub {
  my ($infh) = @_;
  my $d1 = $uint32->($infh);
  my $d2 = $uint16->($infh);
  my $d3 = $uint16->($infh);
  my $d_rest = Binary::MakeType::make_counted_array(sub {8}, $uint8)->($infh);
  no warnings 'portable';
  sprintf("{%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}", $d1, $d2, $d3, @$d_rest);
};



#0076_0000  ea d0 ff 00 f0 00 00 00  00 00 00 00 00 00 27 2d  |..............'-|
#           78 e5 8c 8c 3d 8a 1c 4f  99 35 89 61 85 c3 2d d3
#0076_0010  78 e5 8c 8c 3d 8a 1c 4f  99 35 89 61 85 c3 2d d3  |x...=..O.5.a..-.|
#           fvlength...............  signature.. attributes.   ........_FVH
#                 vv--- this is the problem.  0x0A = \n, . = anything but \n, unless /s.
#0076_0020  00 00 0a 00 00 00 00 00  5f 46 56 48 ff fe 03 00  |........_FVH....|

while ($rom =~ m/(\x78\xe5\x8c\x8c\x3d\x8a\x1c\x4f\x99\x35\x89\x61\x85\xc3\x2d\xd3)........_FVH/gs) {
  my $pos = pos($rom) - 44;
  seek($infh, $pos, 0);
  say "NEW VOLUME";
  system('hd', -n => 0x100, -s => $pos, $infn);
  
  my $volume_header_start = tell($infh);
  my $volume_header = Binary::MakeType::make_struct_array([
                                                           ZeroVector => Binary::MakeType::make_counted_string(sub {16}),
                                                           FileSystemGuid => Binary::MakeType::make_enum($guid,
                                                                                                         {
                                                                                                          lc '{8C8CE578-8A3D-4f1c-9935-896185C32DD3}' => 'fs2',
                                                                                                          lc '{5473C07A-3DCB-4dca-BD6F-1E9689E7349A}' => 'fs3',
                                                                                                         }),
                                                           FvLength => $uint64,
                                                           Signature => Binary::MakeType::make_counted_string(sub {4}),
                                                           Attributes => Binary::MakeType::make_bitmask($uint32,
                                                                                                        {
                                                                                                         1=>'read_disabled_cap',
                                                                                                         2=>'read_enabled_cap',
                                                                                                         4=>'read_status',

                                                                                                         8=>'write_disabled_cap',
                                                                                                         0x10=>'write_enabled_cap',
                                                                                                         0x20=>'write_status',

                                                                                                         0x40=>'lock_cap',
                                                                                                         0x80=>'lock_status',

                                                                                                         0x200=>'sticky_write',
                                                                                                         0x400=>'memory_mapped',
                                                                                                         0x800=>'erase_polarity',

                                                                                                         0x1000=>'read_lock_cap',
                                                                                                         0x2000=>'read_lock_status',
                                                                                                         0x8000_0000 => 'weak_alignment',
                                                                                                         # ... not bothering to define all the alignment constants for now.
                                                                                                        }),
                                                           HeaderLength => $uint16,
                                                           Checksum => $uint16,
                                                           ExtHeaderOffset => $uint16,
                                                           Reserved => $uint8,
                                                           Revision => $uint8,
                                                           # Fixme: should be until a terminator of {0,0}.
                                                           BlockMap => Binary::MakeType::make_counted_array(
                                                                                                            sub{2},
                                                                                                            Binary::MakeType::make_struct_array([
                                                                                                                                                 NumBlocks => $uint32,
                                                                                                                                                 Length => $uint32
                                                                                                                                                ])),
                                                          ])->($infh);
  p $volume_header;

  # Output a .fv file for ambcp?
  if (0) {
    state $volume_index = 0;
    my $out_filename = "$infh.".$volume_index++.".fv";
    open my $fv_fh, ">", $out_filename;
    print $fv_fh substr($rom, $pos, $volume_header->{FvLength});
  }

  my $nextpos_file = tell($infh);
  while (1) {
    say "New file!\n";
    my $current_position = tell($infh);
    my $current_position_rel = $current_position - $volume_header_start;
    say "We were at raw position $current_position = position within volume $current_position_rel";
    my $nextpos_rel = $nextpos_file - $volume_header_start;
    say "We should have been at raw position $nextpos_file = position within volume file $nextpos_rel";
    my $pos_error = $current_position - $nextpos_file;
    say "Positioning error: $pos_error\n";

    seek($infh, $nextpos_file, 0);
    my $pad_to_8 = Binary::MakeType::pad_to(8, $volume_header_start)->($infh);
    say "Padding: $pad_to_8";
    my $file_header_start = tell($infh);
    
    if ($file_header_start >= $volume_header_start + $volume_header->{FvLength}) {
      say "End of volume found!";
      last;
    } else {
      say "Size left in volume: ", $volume_header_start+$volume_header->{FvLength}-$file_header_start;
    }
    print "New file!\n";
    my $file_header = Binary::MakeType::make_struct_array([
                                                           _start_pos => sub {tell shift},
                                                           Name => $guid,
                                                           IntegrityCheckHeader => $uint8,
                                                           IntegrityCheckFile => $uint8,
                                                           Type => Binary::MakeType::make_enum($uint8,
                                                                                               {
                                                                                                1 => 'raw',
                                                                                                2 => 'freeform',
                                                                                                3 => 'security_core',
                                                                                                4 => 'pei_core',
                                                                                                5 => 'dxe_core',
                                                                                                6 => 'peim',
                                                                                                7 => 'driver',
                                                                                                8 => 'combined_peim_driver',
                                                                                                9 => 'application',
                                                                                                0x0a => 'smm',
                                                                                                0x0b => 'firmware_volume_image',
                                                                                                0x0c => 'combined_smm_dxe',
                                                                                                0x0d => 'smm_core',
                                                                                                # 0xc0-0xdf => 'OEM file types',
                                                                                                # 0xe0-0xef => 'debug/test file types',
                                                                                                0xf0 => 'pad',
                                                                                                # 0xf1-0xff => 'firmware file system specific file types'
                                                                                                0xff => 'nonstandard_pad',
                                                                                               }),
                                                           Attributes => Binary::MakeType::make_bitmask($uint8,
                                                                                                        {reverse(
                                                                                                                 large_file => 1,
                                                                                                                 fixed => 4,
                                                                                                                 data_alignment => 0x38,
                                                                                                                 checksum => 0x40,
                                                                                                                )
                                                                                                        }),
                                                                                                        # includes size of this header (24 bytes).
                                                           Size => $uint24,
                                                           State => Binary::MakeType::make_bitmask(sub {
                                                                                                     my $raw = $uint8->(@_);
                                                                                                     $raw = 0xFF & (~$raw) if $volume_header->{Attributes}{erase_polarity};
                                                                                                     $raw;
                                                                                                   },
                                                                                                   {
                                                                                                    1 => 'header_construction',
                                                                                                    2 => 'header_valid',
                                                                                                    4 => 'data_valid',
                                                                                                    8 => 'marked_for_update',
                                                                                                    0x10 => 'deleted',
                                                                                                    0x20 => 'header_invalid',
                                                                                                   }),
                                                           # If attributes->{ExtendedSize}, then a uint12 extendedsize, and size above should be 0.
                                                          ])->($infh);
    p $file_header;
    last if $file_header->{State}{header_invalid};
    if ($file_header->{Type} eq 'nonstandard_pad') {
      say "Found type 0xFF, assuming end of filesystem";
      last;
    }
    $nextpos_file = $file_header_start + $file_header->{Size};

    # if ($file_header->{Type} eq 'raw' and $file_header->{Name} eq '{cef5b9a3-476d-497f-9fdc-e98143e0422c}') {
    #   while (1) {
    #     # AMI-style EFI variables.
    #     my $var_header_start = tell($infh);
    #     last if ($var_header_start >= $file_header_start + $file_header->{Size});
    #     say "offset within file: ", $var_header_start - $file_header_start;
    #     say "file size: ", $file_header->{Size};
    #     my $var_header = Binary::MakeType::make_struct_array([
    #                                                           magic => Binary::MakeType::make_constant_string('NVAR'),
    #                                                           size => $uint16,
    #                                                           next => $uint24,
    #                                                           attributes => Binary::MakeType::make_bitmask($uint8,
    #                                                                                                        {
    #                                                                                                         1 => 'runtime_access',
    #                                                                                                         2 => 'desc_ascii',
    #                                                                                                         4 => 'guid',
    #                                                                                                         8 => 'data',
    #                                                                                                         0x10 => 'exthdr',
    #                                                                                                         0x40 => 'authwr',
    #                                                                                                         0x20 => 'hardware_error_record',
    #                                                                                                         0x80 => 'valid',
    #                                                                                                        }),
    #                                                           # GUID, if attributes guid.
    #                                                           # GUID index, if !attributes guid.
    #                                                          ])->($infh);
        
    #     # https://github.com/chipsec/chipsec/blob/master/source/tool/chipsec/hal/uefi_platform.py
    #     if (!$var_header->{size}) {
    #       say "Bollocks, didn't get expected magic";
    #       system('hd', -n => $file_header->{Size} - ($var_header_start - $file_header_start), -s => $var_header_start, $infn);
    #       last;
    #     }
    #     if ($var_header->{attributes}{guid}) {
    #       $var_header->{guid} = $guid->($infh);
    #     } else {
    #       my $guid_index  = $uint8->($infh);
    #       my $saved_pos = tell($infh);
    #       my $computed_pos = $file_header_start + $file_header->{Size} - 16*($guid_index+1);
    #       seek($infh, $computed_pos, 0);
    #       $var_header->{guid} = $guid->($infh);
    #       seek($infh, $saved_pos, 0);
    #     }
    #     if ($var_header->{attributes}{desc_ascii}) {
    #       $var_header->{desc} = Binary::MakeType::make_encoded_string('utf8')->($infh);
    #     }
    #     my $expected_pos = $var_header_start + $var_header->{size};
    #     my $current_pos = tell($infh);
    #     my $offset = $expected_pos - $current_pos;
    #     $var_header->{data_len} = $offset;
    #     $var_header->{data} = Binary::MakeType::make_counted_string(sub {$offset})->($infh);


    #     # Known variables are listed in UEFI spec version 2.4 section 3.2.
    #     print "UEFI variable: ";
    #     print $var_header->{desc}
    #       if (defined $var_header->{desc});
    #     print ": ";
    #     print $var_header->{guid};
    #     print ": ";
    #     print $var_header->{data};
    #     print "\n";
    #     $variables->{$var_header->{desc} || $var_header->{guid}} = $var_header->{data};

    #     if (not defined $var_header->{desc}) {
    #       # nop
    #     } elsif ($var_header->{desc} eq 'MonotonicCounter') {
    #       # This isn't listed in uefi spec sec 3.2, but is presumably used to implement the GetNextMonotonicCount() function of section 7.5.2.
    #     } elsif ($var_header->{desc} eq 'Timeout') {
    #       printf " Boot keyboard selection timeout: %d seconds\n", unpack 's', $var_header->{data};
    #     } elsif ($var_header->{desc} eq 'Lang') {
    #       printf " Language: %s\n", $var_header->{data};
    #     } elsif (grep {$var_header->{desc} eq $_} qw<ConOut ConIn ErrOut ConInDev ConOutDev ErrOutDev>) {
    #       open my $memfh, '<', \$var_header->{data};
    #       print $type_device_path->($memfh);
    #     } elsif ($var_header->{desc} =~ m/^Boot([0-9A-Fa-f]{4})$/) {
    #       # Contains an EFI_LOAD_OPTION, defined in section 3.1.3 of the main uefi spec.
    #       open my $loadoption_fh, '<', \$var_header->{data};
    #       my $loadoption_struct = Binary::MakeType::make_struct_array([
    #                                                                    Attributes => $uint32,
    #                                                                    FilePathListLength => $uint16,
    #                                                                    Description => Binary::MakeType::make_encoded_string('utf16le'),
    #                                                                   ]);
    #       print "EFI_LOAD_OPTION\n";
    #       my $option = $loadoption_struct->($loadoption_fh);
    #       my $fpl_start = tell($loadoption_fh);
    #       while (1) {
    #         my $relpos = tell($loadoption_fh) - $fpl_start;
    #         say "Rel. pos within FilePathList: $relpos";
    #         say "Total length of FilePathList: ", $option->{FilePathListLength};
    #         last if ($relpos >= $option->{FilePathListLength});
    #         push @{$option->{FilePathList}}, $type_device_path->($loadoption_fh);
    #         p $option;
    #       }

    #       # ...and then the OptionalData, which is passed on to the image as an argument.
    #       p $option;
    #       # FilePathList => $type_device_path, # A device path, as above.
    #       # OptionalData => $uint32, # passed as arguments to the file?
    #     } elsif ($var_header->{desc} eq 'BootOrder') {
    #       # array of uint16, order of Boot#### elements.
    #     } else {
    #       say "Not a well-known type";
    #     }
    #     # if ($expected_pos != $current_pos) {
    #     #   say "Expected position of next header: $expected_pos, current pos: $current_pos, offset: $offset";
    #     #   seek ($infh, $expected_pos, 0);
    #     # }
    #     p $var_header;
    #   }
    # }

    # Raw files, by definition, have no section headers.
    if ($file_header->{Type} eq 'pad') {
      # File claims to be padding.  We should possibly check if that's really all that it is...
      next;
    }
    
    if ($file_header->{Type} eq 'raw') {
      my $raw_offset = tell($infh);
      my $size = $file_header->{Size};
      my $header_size = $raw_offset - $file_header_start;
      say "Raw file, offset $raw_offset, size=", $file_header->{Size};
      $size -= $header_size;
      say "After adjusting size by $header_size, size=$size";
      my $guid = $file_header->{Name};
      my $out_file_name = file("$infn-$guid/$raw_offset.raw");
      say "file: $out_file_name";
      say "owning dir: ", $out_file_name->dir;
      make_path($out_file_name->dir, {verbose => 1});
      open my $outfh, '>', $out_file_name or die "Can't open $out_file_name for writing: $!";
      print $outfh Binary::MakeType::make_counted_string(sub {$size})->($infh);
      say "Written out to $out_file_name\n";

      seek($infh, $file_header_start+$file_header->{Size}, 0);

      next;
    }

    my $sections = [];
    do_sections($file_header, $infh, $sections);

    print "After reading sections, position=", tell($infh), "\n";
    print "Expected position=", $file_header_start+$file_header->{Size}, "\n";
    print "Position error=", tell($infh)-($file_header_start+$file_header->{Size}), "\n";
    
    seek($infh, $file_header_start+$file_header->{Size}, 0) or die;
  }
}

sub do_sections {
  my ($file_header, $infh, $sections) = @_;
  my $nextpos = tell($infh);
  while (1) { # sections
    say "New section!";
    my $current_position = tell($infh);
    my $current_position_rel = $current_position - $file_header->{_start_pos};
    say "We were at raw position $current_position = position within file $current_position_rel";
    my $nextpos_rel = $nextpos - $file_header->{_start_pos};
    say "We should have been at raw position $nextpos = position within current file $nextpos_rel";
    my $pos_error = $current_position - $nextpos;
    say "Positioning error: $pos_error\n";
    
    seek($infh, $nextpos, 0);
    my $pad = Binary::MakeType::pad_to(4, $file_header->{_start_pos})->($infh);
    say "Padded by ", length($pad);
    my $section_header_start = tell($infh);
    
    #if ($next_pos % 4) {
    #  seek($infh, $header_start + (4 - ($rel_pos % 4)), 0);
    #  $header_start = tell($infh);
    #  $rel_pos = $header_start - $file_header_start;
    #  say "Position within current file: $rel_pos";
    #}
    
    if ($section_header_start >= $file_header->{_start_pos} + $file_header->{Size}) {
      say "That was the last section of this file";
      last;
    }
    
    my $header = Binary::MakeType::make_struct_array([
                                                      _pad_4 => Binary::MakeType::pad_to(4, $file_header->{_start_pos}),
                                                      _header_start_pos => sub {tell shift},
                                                      Size => $uint24,
                                                      Type => Binary::MakeType::make_enum($uint8,
                                                                                          {
                                                                                           0 => 'all',
                                                                                           1 => 'compression',
                                                                                           2 => 'guid_defined',
                                                                                           3 => 'disposable',
                                                                                           # discontinuity
                                                                                           0x10 => 'pe32',
                                                                                           0x11 => 'pic',
                                                                                           0x12 => 'te',
                                                                                           0x13 => 'dxe_depex',
                                                                                           0x14 => 'version',
                                                                                           # friendly name.
                                                                                           0x15 => 'user_interface',
                                                                                           0x16 => 'compatability_16',
                                                                                           # A sub-volume with it's own _FVH signature, etc.
                                                                                           0x17 => 'volume',
                                                                                           0x18 => 'freeform_subtype_guid',
                                                                                           0x19 => 'raw',
                                                                                           # discontinuity
                                                                                           0x1b => 'pei_depex',
                                                                                           0x1c => 'smm_depex',
                                                                                          }),
                                                      # if listed Size is 0xFFFFFF.
                                                      #ExtendedSize => $uint32,
                                                      _header_end_pos => sub {tell shift},
                                                     ])->($infh);
    my $postheader_pos = tell($infh);
    p $header;
    $nextpos = $section_header_start + $header->{Size};
    
    if ($header->{Type} eq 'freeform_subtype_guid') {
      my $subtype_guid = $guid->($infh);
      print "Subtype GUID is: $subtype_guid\n";
      my $post_guid_pos = tell($infh);
      my $used_length = $post_guid_pos - $section_header_start;
      my $remaining_length = $header->{Size} - $used_length;
      
      my $out_filename = file("$infn-".$file_header->{Name}.".".$file_header->{Type}."/".$subtype_guid);
      make_path($out_filename->dir, {verbose=>1});
      open my $outfh, '>', $out_filename or die "Can't open $out_filename: $!";
      seek $infh, $post_guid_pos, 0;
      print $outfh Binary::MakeType::make_counted_string(sub {$remaining_length})->($infh);
    } elsif ($header->{Type} eq 'compression') {
      my $comp_header = Binary::MakeType::make_struct_array([
                                                             _Start => sub {tell($_[0])},
                                                             UncompressedLength => $uint32,
                                                             CompressionType => $uint8,
                                                             _End => sub {tell($_[0])},
                                                            ])->($infh);
      p $comp_header;
      
      my $header_len = $comp_header->{_End} - $comp_header->{_Start};
      my $raw = Binary::MakeType::make_counted_string(sub {$header->{Size} - $header_len - 4})->($infh);
      say "Size of raw: ", length($raw);
      say "Size from section header: ", $header->{Size};
      say "Size of compression header: ", $header_len;
      
      if ($comp_header->{CompressionType} == 1) {
        open my $compressed_temp, ">", "/tmp/asdf";
        print $compressed_temp $raw;
        close $compressed_temp;
        my $raw_done = `/mnt/shared/projects/motherboards/UEFITool/jmm < /tmp/asdf`;
        die if !$raw;
        
        my $got_len = length($raw_done);
        if ($comp_header->{UncompressedLength} != $got_len) {
          die "Warning: expected uncompressed length (", $comp_header->{UncompressedLength}, ") != actual uncompressed length (", $got_len, ")";
        }
        
        my $out_filename = file("$infn-".$file_header->{Name}.".".$file_header->{Type}."/uncompressed");
        make_path($out_filename->dir, {verbose=>1});
        open my $outfh, '>', $out_filename or die "Can't open $out_filename: $!";
        print $outfh $raw_done;
        close $outfh;
        open my $decompressed_infh, '<', $out_filename or die;
        say "Trying inside decompressed bit for more sections";
        my $new_file_header = {%$file_header};
        $new_file_header->{_start_pos} = 0;
        $new_file_header->{Size} = $comp_header->{UncompressedLength};
        p $new_file_header;

        do_sections($new_file_header, $decompressed_infh, $sections);
        unlink $out_filename;
      } else {
        die "Compression type $comp_header->{CompressionType} not handled\n";
      }
    } elsif ($header->{Type} eq 'user_interface') {
      my $out_filename = file("$infn-".$file_header->{Name}.".".$file_header->{Type}."/".$header->{Type});
      make_path($out_filename->dir,
                {
                 verbose => 1
                }
               );
      open my $outfh, '>', $out_filename or die "Can't open $out_filename: $!";
      seek $infh, $postheader_pos, 0;
      my $name = Binary::MakeType::make_counted_string(sub {$header->{Size} - ($postheader_pos - $section_header_start)})->($infh);
      # The .user_interface file gets output with the raw data in it.
      print $outfh $name;
      {
        local $/="\0";
        $name = decode('utf16le', $name);
        chomp $name;
      }
      my $old_dirname = $out_filename->dir;
      my $new_dirname = "$infn-$name.".$file_header->{Type};
      rename $old_dirname, $new_dirname or die "Can't rename $old_dirname to $new_dirname: $!";
    } else {
      my $out_filename = file("$infn-".$file_header->{Name}.".".$file_header->{Type}."/".$header->{Type});
      make_path($out_filename->dir,
                {
                 verbose => 1
                }
               );
      open my $outfh, '>', $out_filename or die "Can't open $out_filename: $!";
      seek $infh, $postheader_pos, 0;
      print $outfh Binary::MakeType::make_counted_string(sub {$header->{Size} - ($postheader_pos - $section_header_start)})->($infh);
    }
  }
}

__END__

while ($rom =~ m/MZ/g) {
  # Pos is the position of the *end* of the match.
  my $pos = pos($rom) - 2;
  #printf "Found MZ at position 0x%x\n", $pos;
  
  my $pe_offset = unpack('S<', substr($rom, $pos+0x3c, 2));
  #printf "PE offset is 0x%x\n", $pe_offset;
  
  my $pe_signature = unpack('a4', substr($rom, $pos+$pe_offset, 4));
  if ($pe_signature ne "PE\0\0") {
    #say "PE signature not found at PE offset, skipping";
    #say "(Got $pe_signature)";
    next;
  }
  
  print "$prev_end - $pos: Unknown stuff (not part of a MZ/PE executable)\n";
  system('hd', -n => ($pos - $prev_end), -s => $prev_end, $infn);

  
  print "PE header:\n";
  system('hd', -n => 128, -s => $pos+$pe_offset, $infn);
  
  seek($infh, $pos+$pe_offset+4, 0);
  
  # IMAGE_NT_HEADERS: https://msdn.microsoft.com/en-gb/library/windows/desktop/ms680336%28v=vs.85%29.aspx
  # IMAGE_FILE_HEADER: https://msdn.microsoft.com/en-gb/library/windows/desktop/ms680313(v=vs.85).aspx
  my $image_header = $image_file_header->($infh);
  p $image_header;

  my $optional_header_pos = tell($infh);
  
  # FIXME: Don't try to read past $image_header->{SizeOfOptionalHeader}.
  my $optional_header = Binary::MakeType::make_struct_array([
                                                             Magic => Binary::MakeType::make_enum($word,
                                                                                                  {
                                                                                                   0x10b => 'PE32',
                                                                                                   0x20b => 'PE32+',
                                                                                                   0x107 => 'rom'
                                                                                                  }),
                                                             MajorLinkerVersion      => $byte,
                                                             MinorLinkerVersion      => $byte,
                                                             SizeOfCode              => $dword,
                                                             SizeOfInitializedData   => $dword,
                                                             SizeOfUninitializedData => $dword,
                                                             AddressOfEntryPoint     => $dword,
                                                             BaseOfCode              => $dword,
                                                             # In PE32, but not PE32+.
                                                             BaseOfData              => $dword,
                                                             # 
                                                             ImageBase => $dword,
                                                             SectionAlignment => $dword,
                                                             FileAlignment => $dword,
                                                             MajorOperatingSystemVersion => $word,
                                                             MinorOperatingSystemVersion => $word,
                                                             MajorImageVersion => $word,
                                                             MinorImageVersion => $word,
                                                             MajorSubsystemVersion => $word,
                                                             MinorSubsystemVersion => $word,
                                                             Win32VersionValue => $dword,
                                                             SizeOfImage => $dword,
                                                             SizeOfHeaders => $dword,
                                                             CheckSum => $dword,
                                                             Subsystem => Binary::MakeType::make_enum($word,
                                                                                                      {
                                                                                                       0 => 'unknown',
                                                                                                       1 => 'native',
                                                                                                       2 => 'gui',
                                                                                                       3 => 'cui',
                                                                                                       7 => 'posix',
                                                                                                       9 => 'win_ce',
                                                                                                       10 => 'efi_app',
                                                                                                       11 => 'efi_boot_service',
                                                                                                       12 => 'efi_runtime_service',
                                                                                                       13 => 'efi_rom',
                                                                                                       14 => 'xbox',
                                                                                                      }),
                                                             DllCharacteristics => Binary::MakeType::make_bitmask($word,
                                                                                                                  {
                                                                                                                   0x400 => 'no_seh'
                                                                                                                  }),
                                                             SizeOfStackReserve => $dword,
                                                             SizeOfStackCommit => $dword,
                                                             SizeOfHeapReserve => $dword,
                                                             SizeOfHeapCommit => $dword,
                                                             LoaderFlags => $dword,
                                                             NumberOfRvaAndSizes => $dword,
                                                            ])->($infh);
  p $optional_header;
  #                           1      2       3      4            5         6               7     8    9          10  11
  my @extra_header_names = ('export', #1
                            'import', #2
                            'resource', #3
                            'exception', #4
                            'certificate', #5
                            'base_relocation', #6
                            'debug', #7
                            'arch', #8
                            'global_ptr', #9
                            'tls', #10
                            'load_config', #11
                            'bound_import', #12
                            'iat', #13
                            'delay_import', #14
                            'clr_runtime', #15
                           );
  my @extra_headers;
  for my $i (0..$optional_header->{NumberOfRvaAndSizes}-1) {
    my $extra_header = Binary::MakeType::make_struct_array([VirtualAddress => $dword,
                                                            Size => $dword
                                                           ])->($infh);
    $extra_header->{name} = $extra_header_names[$i] || 'unknown rva #'.$i;
    push @extra_headers, $extra_header;
  }
  p @extra_headers;
  seek $infh, $optional_header_pos + $image_header->{SizeOfOptionalHeader}, 0;
  
  my $section_header =
    Binary::MakeType::make_counted_array(sub {$image_header->{NumberOfSections}},
                                         Binary::MakeType::make_struct_array([
                                                                              # technically, utf8.  in reality, ascii.
                                                                              # Can (theoretically) start with a slash, in which case mumblemumble long name.
                                                                              Name => Binary::MakeType::make_counted_string(sub {8}),
                                                                              VirtualSize          => $dword,
                                                                              VirtualAddress       => $dword,
                                                                              SizeOfRawData        => $dword,
                                                                              PointerToRawData     => $dword,
                                                                              PointerToRelocations => $dword,
                                                                              PointerToLineNumbers => $dword,
                                                                              NumberOfRelocations  => $word,
                                                                              NumberOfLineNumbers  => $word,
                                                                              Charactersitics      => Binary::MakeType::make_bitmask($dword,
                                                                                                                                     {
                                                                                                                                      0x0000_0020 => 'code',
                                                                                                                                      0x0000_0040 => 'INITIALIZED_DATA',
                                                                                                                                      0x0040_0000 => 'ALIGN_8BYTES',
                                                                                                                                      0x4000_0000 => 'mem_readable',
                                                                                                                                      0x2000_0000 => 'mem_execable',
                                                                                                                                      0x8000_0000 => 'mem_writeable',
                                                                                                                                     }),
                                                                             ])
                                        )->($infh);
  p $section_header;

  my $end=0;
  for my $section (@$section_header) {
    my $this_end = $section->{SizeOfRawData} + $section->{PointerToRawData};
    if ($end < $this_end) {
      $end = $this_end;
    }
    my $name = $section->{Name};
    $name =~ s/\0+$//;
    printf "After %-8s: end=%d\n", $name, $end;

  }

  $prev_end = $pos + $end;
  seek($infh, $prev_end, 0);
  my $postfix_header = Binary::MakeType::make_struct_array([
                                                            u1 => $word,
                                                            u2 => $word,
                                                            name => Binary::MakeType::make_encoded_string('utf16le'),
                                                           ])->($infh);
  my $name = $postfix_header->{name};
  my $out_name = "$infn-$name.exe";
  my $raw = substr($rom, $pos, $end);
  open my $outfh, '>', $out_name or die "Can't open $out_name for writing: $!";
  print $outfh $raw;

  say "Postfix header:\n";
  p $postfix_header;
  $prev_end = tell($infh);

}

my $pos = -s $infn;
print "$prev_end - $pos: Unknown stuff (not part of a MZ/PE executable)\n";
system('hd', -n => ($pos - $prev_end), -s => $prev_end, $infn);
