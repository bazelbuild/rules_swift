#!/bin/bash

set -euo pipefail

readonly bundle_path="$1/Contents/MacOS"
readonly binary=$2
copied_binary="$bundle_path/$(basename "$binary")"

mkdir -p "$bundle_path"
cp -cL "$binary" "$copied_binary"

rpaths=$(otool -l "$copied_binary" \
  | grep -A2 LC_RPATH \
  | grep "^\s*path" | cut -d " " -f 11)

for rpath in $rpaths
do
  if [[ $rpath == @loader_path/* || $rpath == @executable_path/* ]]; then
    prefix="${rpath%%/*}"
    suffix="${rpath#*/}"
    xcrun install_name_tool -rpath "$rpath" "$prefix/../../../$suffix" "$copied_binary"
  fi
done
