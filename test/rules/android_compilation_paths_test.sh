#!/usr/bin/env bash

set -euo pipefail

saw_archive=false
saw_module=false
for artifact in "$@"; do
  case "$artifact" in
    *.a) saw_archive=true ;;
    *.swiftmodule) saw_module=true ;;
    *) continue ;;
  esac

  # Scan every section, including DWARF and the wrapped Swift module, not just
  # runtime strings. Paths must stay relative even though the worker passes
  # an absolute -resource-dir to the compiler.
  strings_out=$(strings -a "$artifact")
  matches=$(grep -E '(^|=|^-[A-Za-z])/[A-Za-z][A-Za-z0-9_.+-]+/[A-Za-z0-9_.+-]+' <<< "$strings_out" || true)
  if [[ -n "$matches" ]]; then
    echo "error: '$artifact' embeds absolute paths:" >&2
    echo "$matches" >&2
    exit 1
  fi

  if [[ "$artifact" == *.a ]]; then
    # This dbg fixture must actually retain the remapped resource-directory
    # references. Otherwise, stripping debug info could hide a regression.
    if ! grep -qE '^\./external/.*swift-resources/usr/lib/swift_static-' <<< "$strings_out"; then
      echo "error: '$artifact' has no relative Swift SDK debug paths" >&2
      exit 1
    fi
  fi
done

if [[ "$saw_archive" != true || "$saw_module" != true ]]; then
  echo "error: expected both a Swift archive and a Swift module" >&2
  exit 1
fi

echo "ok: Android compilation artifacts contain relative SDK paths and no absolute paths"
