#!/usr/bin/env bash

set -euo pipefail

expansions="$1"

# Require a nested expansion so that missing outputs cannot make this pass.
if ! grep -RE '^// original-source-range: .*@__swiftmacro_' "$expansions"; then
  echo "Expected a nested macro expansion with an intermediate source path" >&2
  exit 1
fi

if grep -RE '^// original-source-range: (/|[A-Za-z]:[\\/])' "$expansions"; then
  echo "Macro expansions contain absolute source paths" >&2
  exit 1
fi
