#!/bin/sh

# Recursively copy the Swift sources from the temporary directory to the permanent one:
cp -R {temporary_output_directory_path}/* {permanent_output_directory_path}

# Touch all of the declared Swift sources that were not created:
SWIFT_SOURCE_FILE_PATHS="{swift_source_file_paths}"
for swift_source_file_path in $SWIFT_SOURCE_FILE_PATHS
do
    [[ -f $swift_source_file_path ]] || touch $swift_source_file_path
done
