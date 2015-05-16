package UEFI;
use strictures 1;
use 5.12.0;
use lib '/mnt/shared/projects/games/talos/lib/';
use Binary::MakeType;
use Encode 'decode';

our $uint8  = Binary::MakeType::make_numeric('u8le');
our $uint16 = Binary::MakeType::make_numeric('u16le');
our $uint24 = sub {
  my ($infh) = @_;
  my ($a, $b, $c) = @{Binary::MakeType::make_counted_array(sub {3}, $uint8)->($infh)};
  ($c<<16) | ($b<<8) | $a;
};
our $uint32 = Binary::MakeType::make_numeric('u32le');
our $uint64 = Binary::MakeType::make_numeric('u64le');

our $guid = sub {
  my ($infh) = @_;
  my $d1 = $uint32->($infh);
  my $d2 = $uint16->($infh);
  my $d3 = $uint16->($infh);
  my $d_rest = Binary::MakeType::make_counted_array(sub {8}, $uint8)->($infh);
  no warnings 'portable';
  sprintf("{%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x}", $d1, $d2, $d3, @$d_rest);
};

our $type_device_path = sub {
  my ($devpath_fh) = @_;
  print "Device Path\n";
  my @full_path;
  while (!eof $devpath_fh) {
    my $type = $uint8->($devpath_fh);
    my $subtype = $uint8->($devpath_fh);
    my $length = $uint16->($devpath_fh);
    my $types = {
                 # main uefi spec, section 9.3.
                 # stringifications are section 9.6.1.
                 1 => {name => 'hardware device path',
                       1 => {name => 'pci device path',
                             code => sub {
                               my $devpath_fh = shift;
                               my $function = $uint8->($devpath_fh);
                               my $device = $uint8->($devpath_fh);
                               printf "%02x.%x\n", $device, $function;
                               return sprintf "Pci(0x%x, 0x%x)", $device, $function;
                             },
                            },
                       4 => {name => 'vendor',
                             code => sub {
                               my ($infh) = @_;
                               my $guid = $guid->($infh);
                               #say "In hardware device path vendor, length=$length";
                               my $data = Binary::MakeType::make_counted_string(sub{$length - 20})->($infh);
                               my $data_hex = $data;
                               $data_hex =~ s/(.)/sprintf "%02x", ord $1/ge;
                               print "GUID: $guid\n";
                               print "data_hex: $data_hex\n";
                               if ($guid eq '{2d6447ef-3bc9-41a0-ac19-4d51d01b4ce6}') {
                                 my $data_str = decode('utf16le', $data);
                                 $data_str =~ s/\0$//;
                                 print "data: '$data_str'\n";
                                 $data_hex = qq<"$data_str">;
                               }
                               return "VenHw($guid, $data_hex)";
                             },
                            },
                       5 => {name => 'controller',
                             code => sub {
                               my $n = $uint32->(shift);
                               return "Controller($n)",
                             }
                            },
                      },
                 2 => {name => 'acpi device path',
                       1 => {name => 'acpi device path',
                             code => sub {
                               my $devpath_fh = shift;
                               my $hid = $uint32->($devpath_fh);
                               my $uid = $uint32->($devpath_fh);
                               #say "HID: $hid\n";
                               # Decode the HID from a 32 bit integer to three characters + 16 bit integer.
                               my $nice_hid = '';
                               for my $char (0..2) {
                                 my $shift = $char * 5;;
                                 #say "shift=$shift\n";
                                 my $charval = ($hid >> $shift) & 0b11111;
                                 # 1 is A, not 0.
                                 $charval = $charval + ord('A') - 1;
                                 $nice_hid .= chr($charval);
                               }
                               $nice_hid .= sprintf("%04x", $hid >> 16);
                               #say "HID (decoded): $nice_hid";
                               #say "UID: $uid";
                               if ($hid eq 'PNP0a03') {
                                 return "PciRoot($uid)";
                               } else {
                                 return "Acpi($nice_hid, $uid)";
                               }
                             }
                            },
                       3 => {name => 'acpi _ADR device path',
                             code => sub {
                               # FIXME: if length > 8, then there can be multple _ADRs.
                               my $adr = $uint32->(@_);
                               printf "_ADR: 0x%x\n", $adr;
                               sprintf "AcpiAdr(0x%x)", $adr;
                             },
                            },
                      },
                 3 => {name => 'messaging device path',
                       1 => {name => 'ATAPI',
                             code => sub {
                               my $secondary = $uint8->(@_);
                               my $slave = $uint8->(@_);
                               my $lun = $uint16->(@_);
                               sprintf("Ata(%s, %s, %d)",
                                       ($secondary ? 'Secondary' : 'Primary'),
                                       ($slave ? 'Slave' : 'Master'),
                                       $lun);
                             }
                            },
                       5 => {name => 'USB',
                             code => sub {
                               my $parent_port = $uint8->(@_);
                               my $interface = $uint8->(@_);
                               sprintf "USB(%d, %d)", $parent_port, $interface;
                             }
                            },
                       18 => {name => 'SATA',
                              code => sub {
                                my $hba_port = $uint16->(@_);
                                my $multiplier_port = $uint16->(@_);
                                my $lun = $uint16->(@_);
                                sprintf "Sata(0x%x, 0x%x, 0x%x)", $hba_port, $multiplier_port, $lun;
                              },
                             }
                      },
                 4 => {name => 'media device path',
                       1 => {name => 'hard drive',
                             code => sub {
                               my ($infh) = @_;
                               my $info = Binary::MakeType::make_struct_array([partition_number => $uint32,
                                                                               start_lba => $uint64,
                                                                               size_lba => $uint64,
                                                                               signature => Binary::MakeType::make_counted_string(sub{16}),
                                                                               format => $uint8,
                                                                               signature_type => $uint8,
                                                                              ])->($infh);
                               return "HD($info->{partition_number}, $info->{signature_type}, $info->{start_lba}, $info->{size_lba})";
                             },
                            },
                       4 => {name => 'file',
                             code => sub {
                               my $filename = Binary::MakeType::make_encoded_string('utf16le')->(@_);
                               return qq<"$filename">;
                             },
                            },
                       3 => {name => 'vendor',
                             code => sub {
                               my ($infh) = @_;
                               my $guid = $guid->($infh);
                               #say "In media device path vendor, length=$length";
                               my $data = Binary::MakeType::make_counted_string(sub{$length - 20})->($infh);
                               my $data_hex = $data;
                               $data_hex =~ s/(.)/sprintf "%02x", ord $1/ge;
                               print "GUID: $guid\n";
                               print "data_hex: $data_hex\n";
                               if ($guid eq '{2d6447ef-3bc9-41a0-ac19-4d51d01b4ce6}') {
                                 my $data_str = decode('utf16le', $data);
                                 print "data: '$data_str'\n";
                               }
                               return "VenMedia($guid, $data_hex)";
                             },
                            },
                      },
                 5 => {name => 'bios boot specification path',
                       1 => {name => 'bios boot specification v1.01',
                             code => sub {
                               my ($infh) = @_;
                               my $device_type = $uint16->($infh);
                               $device_type = {
                                               1 => 'Floppy',
                                               2 => 'HD',
                                               3 => 'CDROM',
                                               4 => 'PCMCIA',
                                               5 => 'USB',
                                               6 => 'Network',
                                              }->{$device_type} || $device_type;
                               my $status_flags = $uint16->($infh);
                               my $desc = Binary::MakeType::make_encoded_string('ascii')->($infh);
                               return qq[BBS($device_type, "$desc", $status_flags)];
                             },
                            }
                      },
                 0x7f => {name => 'end of hardware device path',
                          1 => {name => 'End This Instance of a Device Path',
                                # There doesn't seem to be a standard stringification for multiple paths.
                                code => sub {'  AND  '}
                               },
                          0xFF => {name => 'end entire device path',
                                   code => sub {'__LAST__'},
                                  }
                         },
                };
    #say "Type: ", $types->{$type}{name} || $type;
    my $subtype_info = $types->{$type}{$subtype};
    #say "Subtype: ", $subtype_info->{name} || $subtype;
    #say "Length: $length";

    if (!$subtype_info->{code}) {
      say "Type: ", $types->{$type}{name} || $type;
      my $subtype_info = $types->{$type}{$subtype};
      say "Subtype: ", $subtype_info->{name} || $subtype;
      say "Length: $length";

      return "/" . join('/', @full_path);
    }
    my $ret = $subtype_info->{code}($devpath_fh);
    if ($ret eq '__LAST__') {
      last;
    } else {
      push @full_path, $ret;
    }
  }
  return "/" . join('/', @full_path);
};
