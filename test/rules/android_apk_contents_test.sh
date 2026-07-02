#!/usr/bin/env bash

# --- begin runfiles.bash initialization v3 ---
set -uo pipefail; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=;
# --- end runfiles.bash initialization v3 ---

set -euo pipefail

apk="$(rlocation "${ANDROID_APK:?}")"
zipper="$(rlocation "${ANDROID_ZIPPER:?}")"

listing="$("$zipper" v "$apk")"
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  case "$listing" in
    *"$entry"*) ;;
    *) echo "error: APK is missing $entry" >&2; exit 1 ;;
  esac
done <<< "${ANDROID_EXPECTED_ENTRIES:?}"
