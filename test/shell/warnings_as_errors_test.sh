#!/usr/bin/env bash

set -euo pipefail

bazel="${BAZEL:-bazel}"
bazel_build_flags=()
if [[ -n "${BAZEL_BUILD_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  bazel_build_flags=(${BAZEL_BUILD_FLAGS})
fi
log="$(mktemp "${TMPDIR:-/tmp}/warnings_as_errors_test.XXXXXX")"
trap 'rm -f "$log"' EXIT

target="//test/fixtures/warnings_as_errors:forced_downcast_noop"
expected="error (upgraded from warning): forced cast of 'Int' to same type has no effect [forced_downcast_noop]"

if "$bazel" build "${bazel_build_flags[@]}" "$target" &>"$log"; then
  cat "$log"
  echo "Expected $target to fail to build" >&2
  exit 1
fi

if ! grep -Fq "$expected" "$log"; then
  cat "$log"
  echo "Expected failure log to contain: $expected" >&2
  exit 1
fi
