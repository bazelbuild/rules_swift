#!/usr/bin/env bash
# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0

set -euo pipefail

binary="${1:?usage: verify_static_stdlib.sh <binary>}"

if [[ ! -x "$binary" ]]; then
  echo "verify_static_stdlib: binary '$binary' not found or not executable" >&2
  exit 1
fi

if ! command -v readelf >/dev/null 2>&1; then
  echo "verify_static_stdlib: readelf not available; cannot verify" >&2
  exit 1
fi

needed=$(readelf -d "$binary" | awk '/\(NEEDED\)/ {print $NF}' | tr -d '[]')

swift_dyn=$(printf '%s\n' "$needed" | grep -E '^libswift(Core|_Concurrency|_StringProcessing|_RegexParser|Glibc|Dispatch|Foundation)' || true)

if [[ -n "$swift_dyn" ]]; then
  echo "verify_static_stdlib: Swift runtime was dynamically linked — expected static." >&2
  echo "Dynamic swift NEEDED entries:" >&2
  printf '  %s\n' $swift_dyn >&2
  echo >&2
  echo "Full NEEDED list:" >&2
  printf '  %s\n' $needed >&2
  exit 1
fi

echo "verify_static_stdlib: OK — no dynamic Swift runtime NEEDED entries in $binary"
