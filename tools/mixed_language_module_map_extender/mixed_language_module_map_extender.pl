#! /usr/bin/env perl
# ============================================================================ #
# 
# This script processes a C Family module map file to adjust header paths.
# 
# USAGE: mixed_language_module_map_extender.pl <output>                  \
#                                              <modulemap>               \
#                                              <module_name>             \
#                                              <swift_generated_header>
# 
# 
# ============================================================================ #

use strict;
use warnings;
use File::Spec;

# Check arguments
if ( @ARGV != 4 ||
     ( @ARGV == 1 && ( $ARGV[0] eq '-h' || $ARGV[0] eq "--help" ) )
   )
  {
    my $msg = "USAGE: $0 <output> <modulemap> <module_name> " .
              "<swift_generated_header>\n";
    if ( @ARGV == 1 )
      {
        print STDERR $msg;
        exit 0;
      }
    else
      {
        die $msg;
      }
  }

my ( $output, $modulemap, $module_name, $swift_generated_header ) = @ARGV;

# Get absolute paths for directories
my $modulemap_dir = File::Spec->rel2abs(
     ( File::Spec->splitpath( $modulemap ) )[1]
   );
my $output_dir = File::Spec->rel2abs( ( File::Spec->splitpath( $output ) )[1] );

# Open input and output files
open( my $in_fh, '<', $modulemap ) or
    die "Cannot open input file '$modulemap': $!\n";

open( my $out_fh, '>', $output ) or
    die "Cannot open output file '$output': $!\n";


# Process each line of the module map
while ( my $line = <$in_fh> )
  {
    # Match header declarations with optional modifiers
    # ( private, textual, umbrella )
    if ( $line =~ /^(\s*(?:private\s+|textual\s+|umbrella\s+)*)
                   header\s+"([^"]+)"(.*)$/x
       )
    {
      my ( $prefix, $header_path, $suffix ) = ( $1, $2, $3 );
      
      # Convert header path to absolute, then to relative from output directory
      my $original_header_abs = File::Spec->rel2abs(
        $header_path
      , $modulemap_dir
      );
      my $new_header_rel = File::Spec->abs2rel(
        $original_header_abs
      , $output_dir
      );
      
      print $out_fh "${prefix}header \"$new_header_rel\"$suffix\n";
    }
  else
    {
      print $out_fh $line;
    }
  }

# Add Swift submodule
print $out_fh "\n";
print $out_fh "module \"$module_name\".Swift {\n";
print $out_fh "    header \"$swift_generated_header\"\n";
print $out_fh "\n";
print $out_fh "    requires objc\n";
print $out_fh "}\n";

close( $in_fh );
close( $out_fh );
