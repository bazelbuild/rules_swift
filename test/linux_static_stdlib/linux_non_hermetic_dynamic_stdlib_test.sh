#!/usr/bin/env bash

set -euo pipefail

readonly artifact="$1"

dynamic_section="$(readelf -d "$artifact")"
needed_libraries="$(
  sed -n 's/^.*(NEEDED).*Shared library: \[\(.*\)\]$/\1/p' <<<"$dynamic_section"
)"

for library in libswiftCore.so libFoundation.so; do
  if ! grep -Fxq "$library" <<<"$needed_libraries"; then
    echo "error: '$artifact' does not dynamically link $library" >&2
    exit 1
  fi
done

runpath="$(
  sed -n 's/^.*(\(RUNPATH\|RPATH\)).*\[\(.*\)\]$/\2/p' <<<"$dynamic_section"
)"
runtime_dir=""
IFS=: read -ra runpath_entries <<<"$runpath"
for entry in "${runpath_entries[@]}"; do
  if [[ "$entry" = /* ]] &&
      [[ -f "$entry/libswiftCore.so" ]] &&
      [[ -f "$entry/libFoundation.so" ]]; then
    runtime_dir="$entry"
    break
  fi
done

if [[ -z "$runtime_dir" ]]; then
  echo "error: '$artifact' does not have an absolute Swift runtime search path:" >&2
  echo "$runpath" >&2
  exit 1
fi

if [[ "${2:-}" == "--execute" ]]; then
  "$artifact"
fi
