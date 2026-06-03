#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <swiftmodule-file> [--no-default-expected] [expected-string ...]" >&2
  exit 2
fi

readonly swiftmodule="$1"
if [[ ! -f "$swiftmodule" ]]; then
  echo "error: '$swiftmodule' does not exist" >&2
  exit 2
fi
shift

strings_out=$(strings "$swiftmodule")
expected=()
if [[ "${1:-}" == "--no-default-expected" ]]; then
  shift
else
  expected=(
    "-fno-implicit-modules"
    "-fno-implicit-module-maps"
    "-fmodule-file=Foundation="
    "-fmodule-map-file=__bazel_developer_dir"
  )
fi
expected+=("$@")

for option in "${expected[@]}"; do
  if ! grep -qF -- "$option" <<<"$strings_out"; then
    echo "error: '$swiftmodule' is missing expected string: $option: $strings_out" >&2
    exit 1
  fi
done

# Validate that none of the embedded strings carry an absolute path that would
# tie the swiftmodule to the build host. Match three shapes:
#   - `^/foo/bar`         — bare absolute paths
#   - `=/foo/bar`         — paths after `-fmodule-file=Name=`, etc.
#   - `^-[A-Z]/foo/bar`   — paths immediately after `-F`, `-I`, `-iframework`,
#                           and friends (single-token form).
# `/PLACEHOLDER_*` entries are intentional Bazel placeholders that get
# substituted at debug-info consumption time, so they are filtered out.
matches=$(echo "$strings_out" |
  grep -E '(^|=|^-[A-Za-z])/[A-Za-z][A-Za-z0-9_.+-]+/[A-Za-z0-9_.+-]+' |
  grep -Ev '/PLACEHOLDER_' || true)

if [[ -n "$matches" ]]; then
  echo "error: '$swiftmodule' embeds absolute path(s):" >&2
  echo "$matches" >&2
  exit 1
fi

echo "ok: swiftmodule embeds the expected strings without absolute paths"
