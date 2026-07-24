#!/usr/bin/env bash

set -euo pipefail

readonly binary="$1"
readonly objdump="$2"

dynamic_section="$($objdump -p "$binary")"

if ! grep -Eq '^[[:space:]]*NEEDED[[:space:]]+libswiftCore\.so$' <<<"$dynamic_section"; then
  echo "error: '$binary' does not dynamically link libswiftCore.so" >&2
  exit 1
fi

runpath="$(sed -n 's/^[[:space:]]*\(RUNPATH\|RPATH\)[[:space:]]*//p' <<<"$dynamic_section")"
if [[ "$runpath" != *'$ORIGIN/../../_solib_'* ]] ||
    [[ "$runpath" != *'$ORIGIN/uses_dynamic_foundation.runfiles/_main/_solib_'* ]] ||
    [[ "$runpath" != *'swift_Utoolchain_Uubuntu22.04'* ]] ||
    [[ "$runpath" != *'usr_Slib_Sswift_Slinux'* ]]; then
  echo "error: '$binary' does not have the expected Swift runtime search path:" >&2
  echo "$runpath" >&2
  exit 1
fi

"$binary"
