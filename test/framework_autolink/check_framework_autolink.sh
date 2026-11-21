#!/usr/bin/env bash

# Checks that a Swift library's static archive has a `-framework <name>`
# autolink entry. Without it, a binary that links the archive fails with
# undefined symbols from the framework.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <framework-name> <file> [file ...]" >&2
  exit 2
fi

readonly framework="$1"
shift

archives=()
for file in "$@"; do
  [[ "$file" == *.a ]] && archives+=("$file")
done
if [[ ${#archives[@]} -eq 0 ]]; then
  echo "error: no static archive in: $*" >&2
  exit 2
fi

for archive in "${archives[@]}"; do
  if otool -l "$archive" | grep -A1 -- "string #1 -framework$" |
    grep -q -- "string #2 $framework$"; then
    echo "ok: '$archive' autolinks -framework $framework"
    exit 0
  fi
done

echo "error: no '-framework $framework' autolink entry in: ${archives[*]}" >&2
otool -l "${archives[@]}" | grep -A4 LC_LINKER_OPTION >&2 || true
exit 1
