#!/bin/sh

# Recursively copy the Swift sources from the temporary directory to the permanent one:
cp -R {temporary_output_directory_path}/* {permanent_output_directory_path}

# Make the copied files writable:
find {permanent_output_directory_path}/* \
    -exec chmod +w {} ';'

# Touch all of the declared Swift sources to create an empty file if the plugin didn't generate it:
touch {swift_source_file_paths}
