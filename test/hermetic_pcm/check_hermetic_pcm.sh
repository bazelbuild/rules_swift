#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <pcm-file>" >&2
  exit 2
fi

readonly pcm="$1"
if [[ ! -f "$pcm" ]]; then
  echo "error: '$pcm' does not exist" >&2
  exit 2
fi

# Any string extracted from the PCM that looks like an absolute path — a
# leading '/' followed by two or more segments of typical path characters —
# is a hermeticity violation. The two-segment floor avoids matching random
# binary noise like `/pAnc` or `/z/[` that `strings` routinely surfaces from
# a PCM's payload.
#
# `/PLACEHOLDER_*` entries are intentional Bazel placeholders installed by
# rules_swift's `-file-prefix-map` flags; they get substituted at debug/
# consumption time and aren't real absolute paths that leak Xcode.
matches=$(strings "$pcm" |
  grep -E '^/[A-Za-z][A-Za-z0-9_.+-]+/[A-Za-z0-9_.+-]+' |
  grep -Ev '^/PLACEHOLDER_' || true)

if [[ -n "$matches" ]]; then
  echo "error: '$pcm' contains absolute path(s):" >&2
  echo "$matches" >&2
  exit 1
fi

echo "ok: no absolute paths found in '$pcm'"
