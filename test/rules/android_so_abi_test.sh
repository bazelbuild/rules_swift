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

readelf="$(rlocation "${ANDROID_READELF:?}")"
nm="$(rlocation "${ANDROID_NM:?}")"
apk="$(rlocation "${ANDROID_APK:?}")"
zipper="$(rlocation "${ANDROID_ZIPPER:?}")"
shared_library="${ANDROID_SHARED_LIBRARY:?}"
jni_symbol="${ANDROID_JNI_SYMBOL:?}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
(cd "$tmp_dir" && "$zipper" x "$apk" "$shared_library")
so="$tmp_dir/$shared_library"

header="$("$readelf" -h "$so")"
case "$header" in
  *AArch64*) ;;
  *) echo "error: $so is not an AArch64 ELF" >&2; exit 1 ;;
esac

dynsyms="$("$nm" -D --defined-only "$so")"
case "$dynsyms" in
  *"$jni_symbol"*) ;;
  *) echo "error: JNI symbol $jni_symbol is not exported by $so" >&2; exit 1 ;;
esac

dynamic="$("$readelf" -d "$so")"
# API 28 and 29 recognize Android's private RELR tags, not the standardized
# ELF tags. Check the artifact as well as the linker command line.
case "$dynamic" in
  *"(ANDROID_RELR)"*) ;;
  *) echo "error: $so does not use Android-compatible RELR relocations" >&2; exit 1 ;;
esac
case "$dynamic" in
  *"(RELR)"*) echo "error: $so requires the standard RELR tags introduced in API 30" >&2; exit 1 ;;
  *) ;;
esac

while IFS= read -r library; do
  [[ -n "$library" ]] || continue
  case "$dynamic" in
    *"Shared library: [$library]"*) ;;
    *) echo "error: $so does not list $library in NEEDED" >&2; exit 1 ;;
  esac
done <<< "${ANDROID_NEEDED_LIBRARIES:-}"

while IFS= read -r library; do
  [[ -n "$library" ]] || continue
  case "$dynamic" in
    *"Shared library: [$library]"*) echo "error: $so unexpectedly lists $library in NEEDED" >&2; exit 1 ;;
    *) ;;
  esac
done <<< "${ANDROID_NOT_NEEDED_LIBRARIES:-}"
