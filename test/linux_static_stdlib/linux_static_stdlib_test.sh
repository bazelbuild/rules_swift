#!/usr/bin/env bash

set -euo pipefail

readonly binary="$1"
readonly objdump="$2"

needed_libraries="$($objdump -p "$binary" | sed -n 's/^[[:space:]]*NEEDED[[:space:]]*//p')"
unexpected_libraries="$(grep -E '^(libswift|libFoundation|libdispatch|libBlocksRuntime|libTesting|libXCTest|lib_|libcurl|libxml2)' <<<"$needed_libraries" || true)"

if [[ -n "$unexpected_libraries" ]]; then
  echo "error: '$binary' has unexpected dynamic runtime dependencies:" >&2
  echo "$unexpected_libraries" >&2
  exit 1
fi

"$binary"
