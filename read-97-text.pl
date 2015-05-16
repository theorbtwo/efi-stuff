#!/usr/bin/perl
# -*- cperl -*-
use strictures 1;
use 5.20.0;
use lib '/mnt/shared/projects/games/talos/lib/';
use Binary::MakeType;
use Data::Printer colored => 1, output => 'stdout', return_value => 'pass';
use Scalar::Util 'looks_like_number';
use Encode 'decode';
use lib '/mnt/shared/projects/motherboards/990fxa-gd80/';
use UEFI;
$|=1;

binmode \*STDOUT, ':utf8';

sub num {Binary::MakeType::make_numeric(shift);}
() = $UEFI::uint24;
my $uint24 = $UEFI::uint24;
my $uint8 = num('u8le');
my $u8 = Binary::MakeType::make_numeric('u8');
my $utf8 = Binary::MakeType::make_encoded_string('ascii');
my $utf16 = Binary::MakeType::make_encoded_string('utf16le');
my $guid = $UEFI::guid;

my $efi_date = Binary::MakeType::make_struct_array([
                                                    Year => num('u16'),
                                                    Month => num('u8'),
                                                    Day => num('u8')]);
my $efi_time = Binary::MakeType::make_struct_array([
                                                    Hour => num('u8'),
                                                    Minute => num('u8'),
                                                    Second => num('u8')]);


my $string_id = sub {
  my ($fh, $stuff) = @_;
  my $id = num('u16')->(@_);
  if ($id == 0) {
    return 0;
  } else {
    $stuff->{strings}[$id];
  }
};

my $typed_value = sub {
  my (@args) = @_;
  my ($fh) = @_;
  my $start_pos = tell($fh);
  my $val = Binary::MakeType::make_tagged_struct(num('u8'),
                                                 {
                                                  0=>num('u8'),#EFI_IFR_TYPE_NUM_SIZE_8
                                                  1=>num('u16'),#EFI_IFR_TYPE_NUM_SIZE_16
                                                  2=>num('u32'),#EFI_IFR_TYPE_NUM_SIZE_32
                                                  3=>num('u64'),#EFI_IFR_TYPE_NUM_SIZE_64
                                                  4=>num('u8'),#EFI_IFR_TYPE_BOOLEAN
                                                  5=>$efi_time,#EFI_IFR_TYPE_TIME
                                                  6=>$efi_date,#EFI_IFR_TYPE_DATE
                                                  7=>$string_id,#EFI_IFR_TYPE_STRING
                                                  8=>'EFI_IFR_TYPE_OTHER',
                                                  9=>'EFI_IFR_TYPE_UNDEFINED',
                                                  10=>'EFI_IFR_TYPE_ACTION',
                                                  11=>'EFI_IFR_TYPE_BUFFER',
                                                  12=>'EFI_IFR_TYPE_REF'})->(@args);
  # There is space reserved for Value being up to 64 bits, but we may well have not used all of it.
  my $expected_pos = $start_pos + 64/8;
  my $current_pos = tell($fh);
  # FIXME: I don't know what this +1 does...?
  my $pos_error = $expected_pos - $current_pos + 1;
  my $padding = Binary::MakeType::make_counted_string(sub{$pos_error})->(@args);
  return $val;
};

my $statement_header = Binary::MakeType::make_struct_array([
                                                            # 29.3.8.2.3
                                                            Prompt => $string_id,
                                                            Help => $string_id,
                                                           ]);

my $question_header = Binary::MakeType::make_struct_array([
                                                           Header => $statement_header,
                                                           QuestionId => num('u16'),
                                                           VarStoreId => num('u16'),
                                                           VarStoreInfo => num('u16'),
                                                           Flags => Binary::MakeType::make_bitmask(num 'u8',
                                                                                                   {
                                                                                                    1=>'read_only',
                                                                                                    4=>'callback',
                                                                                                    0x10 => 'reset_required',
                                                                                                    0x80 => 'options_only',
                                                                                                   }),
                                                          ]);

my $generic_leaf_format_expr = sub {
  my ($refop, $stuff, $stack) = @_;
  push @$stack, $refop->{opcode_info}{format}($refop, $stuff);
};


# 29.3.8.3
my $form_ops_basic = [
                          EFI_IFR_ACTION_OP => 0x0C, 'Button question',
                          EFI_IFR_ADD_OP => 0x3A, 'Add two unsigned integers and push the  result.',
                          EFI_IFR_AND_OP => 0x15, 'Push true if both sub-expressions returns  true.',
                          EFI_IFR_ANIMATION_OP => 0x1F, '',
                          EFI_IFR_BITWISE_AND_OP => 0x35, 'Bitwise-AND two unsigned integers and  push the result.',
                          EFI_IFR_BITWISE_NOT_OP => 0x37, 'Bitwise-NOT an unsigned integer and push  the result.',
                          EFI_IFR_BITWISE_OR_OP => 0x36, 'Bitwise-OR two unsigned integers and  push the result.',
                          EFI_IFR_CATENATE_OP => 0x5E, 'Push concatenated buffers or strings.',
                          EFI_IFR_CHECKBOX_OP => 0x06, 'Boolean question',
                          EFI_IFR_CONDITIONAL_OP => 0x50, 'Duplicate one of two expressions  depending on result of the first expression.',
                          EFI_IFR_DATE_OP => 0x1A, 'Date question.',
                          EFI_IFR_DEFAULTSTORE_OP => 0x5C, 'Define a Default Type Declaration',
                          EFI_IFR_DEFAULT_OP => 0x5B, 'Provide a default value for a question.',
                          EFI_IFR_DISABLE_IF_OP => 0x1E, 'Nested statements, questions or options  will not be processed if expression returns  true.',
                          EFI_IFR_DIVIDE_OP => 0x3D, 'Divide one unsigned integer by another  and push the result.',
                          EFI_IFR_DUP_OP => 0x57, 'Duplicate top of expression stack',
                          EFI_IFR_END_OP => 0x29, 'Marks end of scope.',
                          EFI_IFR_EQUAL_OP => 0x2F, 'Push TRUE if two expressions are equal.',
                          EFI_IFR_EQ_ID_ID_OP => 0x13, 'Return true if question value equals  another question value',
                          EFI_IFR_EQ_ID_VAL_LIST_OP => 0x14, 'Return true if question value is found in list  of UINT16s',
                          EFI_IFR_EQ_ID_VAL_OP => 0x12, 'Return true if question value equals  UINT16',
                          EFI_IFR_FALSE_OP => 0x47, 'Push a boolean FALSE',
                          EFI_IFR_FIND_OP => 0x4C, 'Find a string in a string.',
                          EFI_IFR_FORM_MAP_OP => 0x5D, 'Create a standards-map form.',
                          EFI_IFR_FORM_OP => 0x01, 'Form',
                          EFI_IFR_FORM_SET_OP => 0x0E, 'Form set',
                          EFI_IFR_GET_OP => 0x2B, 'Return a stored value.',
                          EFI_IFR_GRAY_OUT_IF_OP => 0x19, 'Nested statements, questions or options  will not be selectable if expression returns  true.',
                          EFI_IFR_GREATER_EQUAL_OP => 0x32, 'Push TRUE if one expression is greater  than or equal to another expression.',
                          EFI_IFR_GREATER_THAN_OP => 0x31, 'Push TRUE if one expression is greater  than another expression.',
                          EFI_IFR_GUID_OP => 0x5F, 'An extensible GUIDed op-code',
                          EFI_IFR_IMAGE_OP => 0x04, 'Static image.',
                          EFI_IFR_INCONSISTENT_IF_OP => 0x11, 'Error checking conditional',
                          EFI_IFR_LENGTH_OP => 0x56, 'Push length of buffer or string.',
                          EFI_IFR_LESS_EQUAL_OP => 0x34, 'Push TRUE if one expression is less than  or equal to another expression.',
                          EFI_IFR_LESS_THAN_OP => 0x33, 'Push TRUE if one expression is less than  another expression.',
                          EFI_IFR_LOCKED_OP => 0x0B, 'Marks statement/question as locked',
                          EFI_IFR_MAP_OP => 0x22, 'Convert one value to another by selecting a  match from a list.',
                          EFI_IFR_MATCH_OP => 0x2A, 'Push TRUE if string matches a pattern.',
                          EFI_IFR_MID_OP => 0x4B, 'Extract portion of string or buffer',
                          EFI_IFR_MODAL_TAG_OP => 0x61, 'Specify current form is modal',
                          EFI_IFR_MODULO_OP => 0x3E, 'Divide one unsigned integer by another  and push the remainder.',
                          EFI_IFR_MULTIPLY_OP => 0x3C, 'Multiply two unsigned integers and push  the result.',
                          EFI_IFR_NOT_EQUAL_OP => 0x30, 'Push TRUE if two expressions are not  equal.',
                          EFI_IFR_NOT_OP => 0x17, 'Push false if sub-expression returns true,  otherwise return true.',
                          EFI_IFR_NO_SUBMIT_IF_OP => 0x10, 'Error checking conditional',
                          EFI_IFR_NUMERIC_OP => 0x07, 'Numeric question',
                          EFI_IFR_ONES_OP => 0x54, 'Push a => 0xFFFFFFFFFFFFFFFF.',
                          EFI_IFR_ONE_OF_OP => 0x05, 'One-of question',
                          EFI_IFR_ONE_OF_OPTION_OP => 0x09, 'Option',
                          EFI_IFR_ONE_OP => 0x53, 'Push a one',
                          EFI_IFR_ORDERED_LIST_OP => 0x23, 'Set question',
                          EFI_IFR_OR_OP => 0x16, 'Push true if either sub-expressions returns  true.',
                          EFI_IFR_PASSWORD_OP => 0x08, 'Password string question',
                          EFI_IFR_QUESTION_REF1_OP => 0x40, 'Push a question’s value',
                          EFI_IFR_QUESTION_REF2_OP => 0x41, 'Push a question’s value',
                          EFI_IFR_QUESTION_REF3_OP => 0x51, 'Push a question’s value from a different form.',
                          EFI_IFR_READ_OP => 0x2D, 'Provides a value for the current question or  default.',
                          EFI_IFR_REFRESH_ID_OP => 0x62, 'Establish an event group for refreshing a  forms-based element.',
                          EFI_IFR_REFRESH_OP => 0x1D, 'Interval for refreshing a question',
                          EFI_IFR_REF_OP => 0x0F, 'Cross-reference statement',
                          EFI_IFR_RESET_BUTTON_OP => 0x0D, 'Reset button statement',
                          EFI_IFR_RULE_OP => 0x18, 'Create rule in current form.',
                          EFI_IFR_RULE_REF_OP => 0x3F, 'Evaluate a rule',
                          EFI_IFR_SECURITY_OP => 0x60, 'Returns whether current user profile  contains specified setup access privileges.',
                          EFI_IFR_SET_OP => 0x2C, 'Change a stored value.',
                          EFI_IFR_SHIFT_LEFT_OP => 0x38, 'Shift an unsigned integer left by a number  of bits and push the result.',
                          EFI_IFR_SHIFT_RIGHT_OP => 0x39, 'Shift an unsigned integer right by a number  of bits and push the result.',
                          EFI_IFR_SPAN_OP => 0x59, 'Return first matching/non-matching character in a string',
                          EFI_IFR_STRING_OP => 0x1C, 'String question',
                          EFI_IFR_STRING_REF1_OP => 0x4E, 'Push a string',
                          EFI_IFR_STRING_REF2_OP => 0x4F, 'Push a string',
                          EFI_IFR_SUBTITLE_OP => 0x02, 'Subtitle statement',
                          EFI_IFR_SUBTRACT_OP => 0x3B, 'Subtract two unsigned integers and push  the result.',
                          EFI_IFR_SUPPRESS_IF_OP => 0x0A, 'Suppress if conditional',
                          EFI_IFR_TEXT_OP => 0x03, 'Static text/image statement',
                          EFI_IFR_THIS_OP => 0x58, 'Push the current question’s value',
                          EFI_IFR_TIME_OP => 0x1B, 'Time question.',
                          EFI_IFR_TOKEN_OP => 0x4D, 'Extract a delimited byte or character string  from buffer or string.',
                          EFI_IFR_TO_BOOLEAN_OP => 0x4A, 'Convert expression to a boolean.',
                          EFI_IFR_TO_LOWER_OP => 0x20, 'Convert a string on the expression stack to  lower case.',
                          EFI_IFR_TO_STRING_OP => 0x49, 'Convert expression to a string',
                          EFI_IFR_TO_UINT_OP => 0x48, 'Convert expression to an unsigned integer',
                          EFI_IFR_TO_UPPER_OP => 0x21, 'Convert a string on the expression stack to  upper case.',
                          EFI_IFR_TRUE_OP => 0x46, 'Push a boolean TRUE.',
                          EFI_IFR_UINT16_OP => 0x43, 'Push a 16-bit unsigned integer.',
                          EFI_IFR_UINT32_OP => 0x44, 'Push a 32-bit unsigned integer',
                          EFI_IFR_UINT64_OP => 0x45, 'Push a 64-bit unsigned integer.',
                          EFI_IFR_UINT8_OP => 0x42, 'Push an 8-bit unsigned integer',
                          EFI_IFR_UNDEFINED_OP => 0x55, 'Push Undefined',
                          EFI_IFR_VALUE_OP => 0x5A, 'Provide a value for a question',
                          EFI_IFR_VARSTORE_DEVICE_OP => 0x27, 'Specify the device path to use for variable  storage.',
                          EFI_IFR_VARSTORE_EFI_OP => 0x26, 'Define a UEFI variable style variable  storage.',
                          EFI_IFR_VARSTORE_NAME_VALUE_OP => 0x25, 'Define a name/value style variable storage.',
                          EFI_IFR_VARSTORE_OP => 0x24, 'Define a buffer-style variable storage.',
                          EFI_IFR_VERSION_OP => 0x28, 'Push the revision level of the UEFI  Specification to which this Forms  Processor is compliant.',
                          EFI_IFR_WARNING_IF => 0x63, 'Warning conditional',
                          EFI_IFR_WRITE => 0x2E, 'Change a value for the current question.',
                          EFI_IFR_ZERO_OP => 0x52, 'Push a zero',
                      ];
my $form_ops_info;
my $section_base = '29.3.8.3.';
my $section_n = 1;
while (@$form_ops_basic) {
  my ($name, $number, $doc) = splice(@$form_ops_basic, 0, 3);
  my $info = {name => $name,
              number => $number,
              doc => $doc,
              doc_ref => $section_base.$section_n++
             };
  
  $form_ops_info->{$number} = $info;
  $form_ops_info->{$name} = $info;
}

{
  my $info = {GREATER_THAN => '>',
              LESS_THAN => '<',
              AND => 'and',
              OR => 'or',
             };
  for my $k (keys %$info) {
    my $v = $info->{$k};
    
    $form_ops_info->{"EFI_IFR_${k}_OP"}{format_expr} = sub {
      my ($ret, $stuff, $stack) = @_;
      my $r = pop @$stack;
      my $l = pop @$stack;
      push @$stack, "($l) $v ($r)";
    };
  }
}

$form_ops_info->{EFI_IFR_TRUE_OP}{format_expr} = sub {
  my ($ret, $stuff, $stack) = @_;
  push @$stack, 'TRUE';
};

$form_ops_info->{EFI_IFR_FORM_SET_OP}{type} = [
                                               Guid => $guid,
                                               FormSetTitle => $string_id,
                                               Help => $string_id,
                                               ClassGuids => Binary::MakeType::make_counted_array(num('u8'), $guid),
                                              ];
$form_ops_info->{EFI_IFR_FORM_SET_OP}{format} = sub {
  my ($formset, $stuff) = @_;
  my $block = format_block($formset->{children}, $stuff);
  return "formset($formset->{FormSetTitle}, {$block})\n";
};

$form_ops_info->{EFI_IFR_REF_OP}{type} = [
                                          Question => $question_header,
                                          Form => num('u16')
                                         ];
$form_ops_info->{EFI_IFR_REF_OP}{format} = sub {sprintf(qq[link_to(form=>0x%x, prompt=>'%s', help=>'%s')\n],
                                                        $_[0]->{Form},
                                                        $_[0]->{Question}{Header}{Prompt},
                                                        $_[0]->{Question}{Header}{Help}
                                                       )};

$form_ops_info->{EFI_IFR_DEFAULTSTORE_OP}{type} = [
                                                   # 29.3.8.3.13
                                                   #  Specifies the name and type of a set of defaults
                                                   DefaultName => $string_id,
                                                   DefaultId => num('u16'),
                                                  ];

$form_ops_info->{EFI_IFR_GUID_OP}{type} = sub {
  # escape hatch for mfgr-specific ops?
  my ($fh, $stuff) = @_;
  my $ret;
  $ret->{guid} = $guid->(@_);
  my $expected_pos = $stuff->{start_pos} + $stuff->{len};
  my $current_pos = tell($fh);
  my $pos_error = $expected_pos - $current_pos;

  if ($ret->{guid} eq '{0f0b1735-87a0-4193-b266-538c38af48ce}') {
    # EFI_IFR_TIANO_GUID -- http://dox.ipxe.org/MdeModuleHii_8h_source.html
    my $extended_opcode = Binary::MakeType::make_enum(num('u8'),
                                                      [qw<label banner timeout class subclass>],
                                                     )->(@_);
    $ret->{extended_opcode} = $extended_opcode;
    
    if ($extended_opcode eq 'class') {
      $ret->{class} = Binary::MakeType::make_enum(num('u16'),
                                                      [qw<non_device disk video network input on_board other>],
                                                 )->(@_);
    } elsif ($extended_opcode eq 'subclass') {
      $ret->{subclass} = Binary::MakeType::make_enum(num('u16'),
                                                     [qw<setup_application general_application front_page single_use>],
                                                    )->(@_);
    } elsif ($extended_opcode eq 'label') {
      $ret->{label} = num('u16')->(@_);
    } else {
      die "Don't know how to handled extended opcode $extended_opcode";
    }
    
  } else {
    $ret->{more} = Binary::MakeType::make_counted_array(
                                                        sub {$pos_error},
                                                        num('u8')
                                                       )->(@_);
  }
  return $ret;
};

$form_ops_info->{EFI_IFR_VARSTORE_OP}{type} = sub {
  my ($fh, $stuff) = @_;
  my $ret;
  # 29.3.8.3.89
  # The guid of the efi variable backing.
  $ret->{var_guid} = $guid->(@_);
  $ret->{var_store_id} = num('u16')->(@_);
  # The size of the efi var backing this varstore, not the size of this op!
  $ret->{size} = num('u16')->(@_);
  $ret->{name} = Binary::MakeType::make_encoded_string('ascii')->(@_);
  $stuff->{varstore}{$ret->{var_store_id}} = $ret;
  return $ret;
};

$form_ops_info->{EFI_IFR_FORM_OP}{type} = [
                                           # 29.3.8.3.24
                                           FormId => num('u16'),
                                           FormTitle => $string_id,
                                          ];
$form_ops_info->{EFI_IFR_FORM_OP}{format} = sub {
  my ($ret, $stuff) = @_;
  
  return sprintf("Form(FormId=>0x%x, FormTitle=>'%s') {%s}",
                 $ret->{FormId}, $ret->{FormTitle},
                 format_block($ret->{children})
                );
};

$form_ops_info->{EFI_IFR_SUPPRESS_IF_OP}{type} = [
                                                  # <just a marker, all the contents is in the scoped ops -- the first one is the expression,
                                                  #  the rest are the statements that are only shown if the expression is false>
                                                 ];
$form_ops_info->{EFI_IFR_SUPPRESS_IF_OP}{format} = sub {
  my ($ret, $stuff) = @_;
  my $children = $ret->{children};
  my ($expr_ret, @block_ret) = @$children;

  my $expr = format_expr($expr_ret, $stuff);
  my $block = format_block(\@block_ret, $stuff);

  my $kind = {EFI_IFR_SUPPRESS_IF_OP => 'suppress',
              EFI_IFR_DISABLE_IF_OP => 'disable',
              EFI_IFR_GRAY_OUT_IF_OP => 'gray_out',
             }->{$ret->{opcode_info}{name}} || $ret->{opcode_info}{name};
  
  "${kind}_if($expr) {$block}";
};
$form_ops_info->{EFI_IFR_DISABLE_IF_OP}{format} = $form_ops_info->{EFI_IFR_SUPPRESS_IF_OP}{format};
$form_ops_info->{EFI_IFR_GRAY_OUT_IF_OP}{format} = $form_ops_info->{EFI_IFR_SUPPRESS_IF_OP}{format};

$form_ops_info->{EFI_IFR_QUESTION_REF1_OP}{type} = [
                                                    # push the question's value
                                                    QuestionId => num('u16'),
                                                   ];
$form_ops_info->{EFI_IFR_QUESTION_REF1_OP}{format} = sub {
  my ($refop) = @_;
  return "question_by_id($refop->{QuestionId})->value";
};
$form_ops_info->{EFI_IFR_QUESTION_REF1_OP}{format_expr} = $generic_leaf_format_expr;

for my $width (qw<8 16 32 64>) {
  $form_ops_info->{"EFI_IFR_UINT${width}_OP"}{type} = [Value => num("u".$width)];
  $form_ops_info->{"EFI_IFR_UINT${width}_OP"}{format} = sub {shift->{Value}};
  $form_ops_info->{"EFI_IFR_UINT${width}_OP"}{format_expr} = $generic_leaf_format_expr;
}

# 29.3.8.3.19-21 (note that some combinations in the regex don't exist in the spec)
for my $left_t (qw<ID VAL VAL_LIST>) {
  for my $right_t (qw<ID VAL VAL_LIST>) {
    $form_ops_info->{"EFI_IFR_EQ_${left_t}_${right_t}_OP"}{type} = sub {
      my ($fh, $stuff) = @_;

      my $ret;
      $ret->{types} = [$left_t, $right_t];
      my $types_types = {
                         ID => num('u16'),
                         VAL => num('u16'),
                         VAL_LIST => Binary::MakeType::make_counted_array(num('u16'), num('u16'))
                        };

      for my $i (0..1) {
        my $t = $ret->{types}[$i];
        $ret->{vals}[$i] = {t => $t, value => $types_types->{$t}->(@_)};
      }

      return $ret;
    };

    $form_ops_info->{"EFI_IFR_EQ_${left_t}_${right_t}_OP"}{format} = sub {
      my ($ret, $stuff) = @_;
      my @stack = ();
      $ret->{opcode_info}{format_expr}($ret, $stuff, \@stack);
      return $stack[0];
    };
    
    $form_ops_info->{"EFI_IFR_EQ_${left_t}_${right_t}_OP"}{format_expr} = sub {
      my ($ret, $stuff, $stack) = @_;

      my @vals;
      for my $side (0..1) {
        my $val_thing = $ret->{vals}[$side];
        if ($val_thing->{t} eq 'ID') {
          $vals[$side] = "question_by_id($val_thing->{value})->value";
        } elsif ($val_thing->{t} eq 'VAL') {
          $vals[$side] = $val_thing->{value};
        } elsif ($val_thing->{t} eq 'VAL_LIST') {
          $vals[$side] = "[" . join(", ", @{$val_thing->{value}}) . "]";
        }
      }

      push @$stack, "$vals[0] ~~ $vals[1]";
    };
  }
}

$form_ops_info->{EFI_IFR_NOT_OP}{type} = [
                                          # FIXME: Confirm
                                          # push @stack, !pop @stack
                                         ];
$form_ops_info->{EFI_IFR_NOT_OP}{format_expr} = sub {
  my ($ret, $stuff, $stack) = @_;
  push @$stack, "!(".pop(@$stack).")";
};

$form_ops_info->{EFI_IFR_END_OP}{type} = [
                                          # $scope_depth--;
                                         ];

$form_ops_info->{EFI_IFR_ONE_OF_OP}{type} = sub {
  my $ret;
  #  29.3.8.3.50
  $ret->{Question} = $question_header->(@_);
  # flags are doumented as being the same as EFI_IFR_NUMERIC, which is 29.3.8.3.47
  $ret->{flags} = num('u8')->(@_);
  $ret->{size} = $ret->{flags} & 0x03;
  $ret->{display} = $ret->{flags} & 0x30;
  
  my $size = 8*(2 ** $ret->{size});
  $ret->{size} = $size;
  my $num_type = num("u$size");
  $ret->{min} = $num_type->(@_);
  $ret->{max} = $num_type->(@_);
  $ret->{step} = $num_type->(@_);
  
  # The size taken by min/max/step is only size-in-bytes * 3, but the op is always
  # sized for 3*64 bits = 3*8 bytes.
  $ret->{padding} = Binary::MakeType::make_counted_string(sub {
                                                            3*8 - 3*$ret->{size}/8
                                                          })->(@_);
  return $ret;
};
$form_ops_info->{EFI_IFR_ONE_OF_OP}{format} = sub {
  my ($one_of, $stuff) = @_;

  my $val = get_varstore_value($one_of->{varstore}, $one_of->{Question}{VarStoreInfo}, $one_of->{size});

  my $kind_text = 'one-of';
  my $is_numeric = 0;
  my $extra_text = '';
  if ($one_of->{opcode_info}{name} eq 'EFI_IFR_NUMERIC_OP') {
    $is_numeric = 1;
    $kind_text = 'numeric';

    $extra_text = sprintf "%d..%d by %d: ", $one_of->{min}, $one_of->{max}, $one_of->{step};
  }

  my $out = '';
  $out .= sprintf "%s: %s$one_of->{Question}{Header}{Prompt}: $val = 0x%x\n", $kind_text, $extra_text, $val;
  my @options = @{$one_of->{children}};
  while (my $option = shift @options) {
    if ($option->{opcode_info}{name} eq 'EFI_IFR_DEFAULT_OP') {
      my $c = $option->{Value}{data} == $val ? 'C' : ' ';
      $out .= sprintf " - [  $c] Default #%d: %d = 0x%x\n", $option->{DefaultId}, $option->{Value}{data}, $option->{Value}{data};
    } elsif ($option->{opcode_info}{name} eq 'EFI_IFR_ONE_OF_OPTION_OP') {
      my $d = $option->{Flags}{default} ? 'D' : ' ';
      my $m = $option->{Flags}{default_mfg} ? 'M' : ' ';
      my $c = $option->{Value}{data} == $val ? 'C' : ' ';
      $out .= sprintf " - [$d$m$c] %d = 0x%x: %s\n", $option->{Value}{data}, $option->{Value}{data}, $option->{Option};
    } elsif ($option->{opcode_info}{name} eq 'EFI_IFR_SUPPRESS_IF_OP') {
      my @children = @{$option->{children}};
      my $test = shift @children;
      push @options, @children;
    } else {
      p $option;
      say "Don't know what to do with above option inside a one_of/numeric";
    }
  }
  return $out;
};

$form_ops_info->{EFI_IFR_NUMERIC_OP}{type} = $form_ops_info->{EFI_IFR_ONE_OF_OP}{type};
$form_ops_info->{EFI_IFR_NUMERIC_OP}{format} = $form_ops_info->{EFI_IFR_ONE_OF_OP}{format};

$form_ops_info->{EFI_IFR_ONE_OF_OPTION_OP}{type} = [
                                                    # 29.3.8.3.51
                                                    Option => $string_id,
                                                    Flags => Binary::MakeType::make_bitmask(num('u8'),
                                                                                            {
                                                                                             0x10 => 'default',
                                                                                             0x20 => 'default_mfg'
                                                                                            }),
                                                    
                                                    Value => $typed_value,
                                                   ];

$form_ops_info->{EFI_IFR_CHECKBOX_OP}{type} = [
                                               # 29.3.8.3.9
                                               Question => $question_header,
                                               Flags => Binary::MakeType::make_bitmask(num('u8'),
                                                                                       {1=>'default',
                                                                                        2=>'default_mfg'}),
                                              ];
$form_ops_info->{EFI_IFR_CHECKBOX_OP}{format} = sub {
  my ($checkbox, $stuff) = @_;
  my $val = get_varstore_value($checkbox->{varstore}, $checkbox->{Question}{VarStoreInfo}, 8);
  print "checkbox: $checkbox->{Question}{Header}{Prompt}: $val\n";
};

$form_ops_info->{EFI_IFR_DEFAULT_OP}{type} = [
                                              # 29.3.8.3.12
                                              DefaultId => num('u16'),
                                              Value => $typed_value,
                                             ];
$form_ops_info->{EFI_IFR_SUBTITLE_OP}{type} = [
                                               # 29.3.8.3.73
                                               Statement => $statement_header,
                                               Flags => Binary::MakeType::make_bitmask(num('u8'),
                                                                                       {1=>'horizontal'}),
                                              ];
$form_ops_info->{EFI_IFR_SUBTITLE_OP}{format} = sub {
  return "subtitle: '$_[0]->{Statement}{Prompt}'\n";
};

$form_ops_info->{EFI_IFR_DATE_OP}{type} = sub {
  my $ret;
  $ret->{Question} = $question_header->(@_);
  $ret->{Flags} = Binary::MakeType::make_bitmask(num('u8'),
                                                 { 0x01 => 'year_suppress',
                                                   0x02 => 'month_suppress',
                                                   0x04 => 'day_suppress',
                                                   0x30 => 'storage',
                                                  })->(@_);
  $ret->{storage} = {0 => 'normal', 0x10 => 'time', 0x20 => 'wakeup'}->{$ret->{Flags}{storage} || 0};
  return $ret;
};
$form_ops_info->{EFI_IFR_DATE_OP}{format} = sub {
  return "<not bothering to format date op>\n";
};

$form_ops_info->{EFI_IFR_TIME_OP}{type} = sub {
  my $ret;
  $ret->{Question} = $question_header->(@_);
  $ret->{Flags} = Binary::MakeType::make_bitmask(num('u8'),
                                                 { 0x01 => 'hour_suppress',
                                                   0x02 => 'minute_suppress',
                                                   0x04 => 'second_suppress',
                                                   0x30 => 'storage',
                                                  })->(@_);
  $ret->{storage} = {0 => 'normal', 0x10 => 'time', 0x20 => 'wakeup'}->{$ret->{Flags}{storage} || 0};
  return $ret;
};
$form_ops_info->{EFI_IFR_TIME_OP}{format} = sub {
  return "<not bothering to format time op>\n";
};

$form_ops_info->{EFI_IFR_TEXT_OP}{type} = [
                                           Statement => $statement_header,
                                           TextTwo => $string_id
                                          ];
$form_ops_info->{EFI_IFR_ACTION_OP}{type} = [
                                             Question => $question_header,
                                             QuestionConfig => $string_id
                                            ];
$form_ops_info->{EFI_IFR_ACTION_OP}{format} = sub {
  my ($action, $stuff) = @_;
  return "button: '$action->{Question}{Header}{Prompt}' -> $action->{QuestionConfig}\n";
};

$form_ops_info->{EFI_IFR_STRING_OP}{type} = [
                                             Question => $question_header,
                                             MinSize => num('u8'),
                                             MaxSize => num('u8'),
                                             Flags => Binary::MakeType::make_bitmask(num('u8'),
                                                                                     {
                                                                                      1=>'multi_line'
                                                                                     })
                                            ];
$form_ops_info->{EFI_IFR_PASSWORD_OP}{type} = [
                                             Question => $question_header,
                                             MinSize => num('u8'),
                                             MaxSize => num('u8'),
                                            ];

my $form_package = sub {
  my ($fh, $stuff) = @_;
  my (@args) = @_;
  
  my $scope_depth = 0;
  my @scope_stack;

  while (1) {
    my $start_pos = tell($fh);
    my $ret = {};
    my $opcode = $u8->($fh);
    my $opcode_info = $form_ops_info->{$opcode};
    my $scope_and_len = $u8->($fh);
    my $scope = $scope_and_len & 0x80;
    my $len = $scope_and_len & 0x7f;
    my $indent = " " x $scope_depth;
    if (!$opcode_info) {
      printf "${indent}Opcode: 0x%x, len: $len, scope: $scope\n", $opcode;
      die "Undefined opcode $opcode\n";
    }
    printf "${indent}Opcode: 0x%x = %s, len: $len, scope: $scope, docref: %s\n", $opcode, $opcode_info->{name}, $opcode_info->{doc_ref};

    $stuff->{start_pos} = $start_pos;
    $stuff->{len} = $len;

    if (!$opcode_info->{type} and $stuff->{len} > 2) {
      die sprintf "Don't know how to parse opcode, section %s: %s", $opcode_info->{doc_ref}, $opcode_info->{doc};
    }
    if (ref $opcode_info->{type} eq 'ARRAY') {
      $opcode_info->{type} = Binary::MakeType::make_struct_array($opcode_info->{type}, $stuff);
    }
    if (!$opcode_info->{type} and $stuff->{len} == 2) {
      $ret = {};
    } else {
      $ret = $opcode_info->{type}($fh, $stuff);
    }
    my $expected_pos = $start_pos + $len;
    my $current_pos = tell($fh);
    my $pos_error = $expected_pos - $current_pos;
    if ($pos_error) {
      say "Expected position: ", $expected_pos;
      say "Current position:  ", $current_pos;
      say "Position error: $pos_error";
      $ret->{mysterous_padding} = Binary::MakeType::make_counted_string(sub{$pos_error})->(@args);
    }
    p $ret;
    $ret->{opcode_info} = $opcode_info;

    if ($scope) {
      push @scope_stack, $ret;
      $scope_depth++;
    } elsif ($opcode_info->{name} eq 'EFI_IFR_END_OP') {
      $scope_depth--;

      my $scope_start = pop @scope_stack;
      if (not $scope_start->{opcode_info}{format}) {
        p $scope_start;
        die "$scope_start->{opcode_info}{name}: No format callback?";
      }
      my $formatted = $scope_start->{opcode_info}{format}->($scope_start, $stuff);
      say $formatted;

      if ($scope_depth <= 0) {
        return;
      }

      push @{$scope_stack[-1]->{children}}, $scope_start;
    } else {
      # Neither begins nor ends a scope
      push @{$scope_stack[-1]->{children}}, $ret;
    }
    
    if ($ret->{Question} and $ret->{Question}{VarStoreId} != 0) {
      my $qh = $ret->{Question};
      my $varstore = $stuff->{varstore}{$qh->{VarStoreId}};
      $ret->{varstore} = $varstore;
      #$varstore->{questions}[$qh->{VarStoreInfo}] = $ret;
    #  my $name = $varstore->{name};
    #  my $guid = $varstore->{var_guid};
    #   $guid =~ s/\{//;
    #   $guid =~ s/\}//;
    #   my $offset = $qh->{VarStoreInfo};
    #   my $command = "sudo hd -s $offset /sys/firmware/efi/vars/$name-$guid/data";
    #   say $command;
    #   system($command);
    #   #print "VARSTORE: \n";
    #   #p $varstore;
    }
  }
  p $stuff->{varstore};
};

my $string = Binary::MakeType::make_tagged_struct($uint8,
                                                  {
                                                   0 => sub {
                                                     '__last__'
                                                   },
                                                   # 0x10 single, scsu
                                                   # 0x11 single, scsu + font
                                                   # 0x12 multiple, scsu
                                                   # 0x13 multiple, scsu + font
                                                   # 0x14 single, ucs2
                                                   0x14 => sub {
                                                     my ($fh, $i, $ret) = @_;
                                                     my $s = Binary::MakeType::make_encoded_string('utf16le')->(@_);
                                                     $ret->[$i++] = $s;
                                                     return $i;
                                                   },
                                                   # 0x15 single, ucs2 + font
                                                   # 0x16 multiple, ucs2
                                                   # 0x17 multiple, ucs2 + font
                                                   # 0x20 duplicate
                                                   0x20 => sub {
                                                     my ($fh, $i, $ret) = @_;
                                                     $ret->[$i+1] = $ret->[$i];
                                                     $i++;
                                                     return $i;
                                                   },
                                                   # 0x21 skip (2 byte count)
                                                   0x21 => sub {
                                                     my ($fh, $i, $ret) = @_;
                                                     $i += num('u16')->($fh);
                                                     return $i;
                                                   },
                                                   # 0x22 skip (1 byte count)
                                                   0x22 => sub {
                                                     my ($fh, $i, $ret) = @_;
                                                     $i += num('u8')->($fh);
                                                     return $i;
                                                   }
                                                  });

my $strings_package = Binary::MakeType::make_struct_array([
                                                           HdrSize => num('u32le'),
                                                           StringInfoOffset => num('u32le'),
                                                           LanguageWindow => Binary::MakeType::make_counted_array(sub {16}, num('u16le')),
                                                           LanguageName => num('u16le'),
                                                           Language => Binary::MakeType::make_encoded_string('ascii'),
                                                           Strings => sub {
                                                             my ($fh) = @_;
                                                             my $ret = ['dummy entry zero'];
                                                             my $i = 1;
                                                             while (1) {
                                                               $i = $string->($fh, $i, $ret);
                                                               $i = $i->{data};
                                                               last if $i eq '__last__';
                                                             }
                                                             return $ret;
                                                           },
                                                          ]);

my $simple_font_narrow_glyph = sub {
  my ($fh) = @_;
  my $plain = Binary::MakeType::make_struct_array([
                                                   UnicodeWeight => num('u16le'),
                                                   Attributes => num('u8'),
                                                   GlyphCol1 => Binary::MakeType::make_counted_array(sub {19}, num('u8'))
                                                  ])->(@_);
  $plain->{picture} = "\n";
  for my $row (@{$plain->{GlyphCol1}}) {
    $plain->{picture} .= sprintf "%08b\n", $row;
  }
  $plain->{picture} =~ tr/01/.#/;

  return $plain;
};

my $simple_font_wide_glyph = sub {
  my ($fh) = @_;
  my $plain = Binary::MakeType::make_struct_array([
                                                   UnicodeWeight => num('u16le'),
                                                   Attributes => num('u8'),
                                                   GlyphCol1 => Binary::MakeType::make_counted_array(sub {19}, num('u8')),
                                                   GlyphCol2 => Binary::MakeType::make_counted_array(sub {19}, num('u8')),
                                                   # Pad so that a wide character is precisely twice the width of a narrow character?
                                                   Pad => Binary::MakeType::make_counted_array(sub {3}, num('u8')),
                                                  ])->(@_);
  $plain->{picture} = "\n";
  for my $row_i (0..@{$plain->{GlyphCol1}}-1) {
    $plain->{picture} .= sprintf "%08b%08b\n", $plain->{GlyphCol1}[$row_i], $plain->{GlyphCol2}[$row_i];
  }
  $plain->{picture} =~ tr/01/.#/;

  return $plain;
};

# my $simple_font_package = Binary::MakeType::make_struct_array([
#                                                                #NumberOfNarrowGlyphs => num('u16le'),
#                                                                #NumberOfWideGlyphs => num('u16le'),
#                                                                ## ... and here is where I want count-from-context availablilty, and shit gets hard.

#                                                                NarrowGlyphs => Binary::MakeType::make_counted_array(num('u32le'),
#                                                                                                                     $simple_font_narrow_glyph),
#                                                               ]);

my $simple_font_package = sub {
  my ($fh) = @_;
  my $ret = {};
  $ret->{NumberOfNarrowGlyphs} = num('u16le')->($fh);
  $ret->{NumberOfWideGlyphs} = num('u16le')->($fh);
  p $ret;
  $ret->{NarrowGlyphs} = Binary::MakeType::make_counted_array(sub {$ret->{NumberOfNarrowGlyphs}}, $simple_font_narrow_glyph)->($fh);
  $ret->{WideGlyphs}  = Binary::MakeType::make_counted_array(sub {$ret->{NumberOfWideGlyphs}}, $simple_font_wide_glyph)->($fh);
  return $ret;
};

my $hii_package = Binary::MakeType::make_struct_array([
                                                       Length => $uint24,
                                                       Body => Binary::MakeType::make_tagged_struct(
                                                                                                    $uint8,
                                                                                                    {
                                                                                                     #1 => 'guid',
                                                                                                     2 => $form_package,
                                                                                                     # 3?
                                                                                                     4 => $strings_package,
                                                                                                     # 5=>font
                                                                                                     # 6=>image
                                                                                                     7 => $simple_font_package,
                                                                                                     # 8=>device path
                                                                                                     # 9=>keyboard layout
                                                                                                     # a=>animations
                                                                                                     # df=>end
                                                                                                     # e0-ff=>system
                                                                                                    })]);
for my $infn (@ARGV) {
  open my $infh, "<", $infn or die "Can't open $infn: $!";
  print "$infn\n";

  my $huh = num('u32')->($infh);
  p $huh;

  my $stuff = {};
  while (!eof $infh) {
    my $x = $hii_package->($infh, $stuff);
    p $x;

    if ($x->{Body} =~ m/^ERROR/) {
      last
    };

    # Any strings is better then no strings, but en-US strings are better then any strings.
    if ($x->{Body}{Strings} and
        (not $stuff->{strings} or
         $x->{Body}{Language} eq 'en-US')) {
      $stuff->{strings} = $x->{Body}{Strings};
    }
  }
}

sub get_varstore_value {
  my ($varstore, $varstoreinfo, $size) = @_;
  # FIXME: Work with other types of varstore, rather then just efi-variable.
  my $name = $varstore->{name};
  my $guid = $varstore->{var_guid};
  $guid =~ s/\{//;
  $guid =~ s/\}//;
  my $offset = $varstoreinfo;

  my $filename = "/sys/firmware/efi/vars/$name-$guid/data";

  if (!-e $filename) {
    say "$filename does not exist (attempting to read offset = $offset, size = $size)";
    return 0;
  }
  
  my $val;
  
  {
    open my $var_fh, "<:raw", $filename or die "opening $filename: $!";
    seek($var_fh, $offset, 0) or die "Can't seek in $filename to $offset: $!";
    $val = num('u'.$size)->($var_fh);
  }

  return $val;
}

sub format_expr {
  my ($op, $stuff) = @_;

  say "format_expr";
  
  my @stack;
  my @todo = $op;
  while (@todo) {
    my $op = shift @todo;
    print "$op->{opcode_info}{name}\n";
    if (!$op->{opcode_info}{format_expr}) {
      die "No format_expr for $op->{opcode_info}{name}";
    }
    $op->{opcode_info}{format_expr}($op, $stuff, \@stack);
    if ($op->{children}) {
      unshift @todo, @{$op->{children}};
    }
  }

  if (@stack == 1) {
    return $stack[0];
  }
  
  p @stack;
  die "Stack does not contain exactly one entry at end of format_expr";
}

sub format_block {
  my ($children, $stuff) = @_;

  if (!$children or !@$children) {
    return "";
  }

  my $out = "\n";
  for my $child (@$children) {
    if ($child->{opcode_info}{format}) {
      $out .= $child->{opcode_info}{format}($child, $stuff);
    } else {
      $out .= "<don't know format for $child->{opcode_info}{name}>\n";
    }
  }

  $out =~ s/\n/\n /g;
  $out =~ s/ +$//g;
  $out .= "\n";

  say "format_block done";
  
  return $out;
}
