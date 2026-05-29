#!/usr/bin/env bash

set -euo pipefail

bazel="${BAZEL:-bazel}"
log="$(mktemp "${TMPDIR:-/tmp}/layering_check_failure_test.XXXXXX")"
trap 'rm -f "$log"' EXIT

check_failure() {
  local target="$1"
  local expected_label="${2:-$target}"
  local expected_module="${3:-TransitiveDependency}"

  if "$bazel" build "$target" &>"$log"; then
    cat "$log"
    echo "Expected $target to fail to build" >&2
    exit 1
  fi

  for expected in \
    "Layering violation in" \
    "$expected_label" \
    "$expected_module" \
    "Please add the correct 'deps'"; do
    if ! grep -Fq "$expected" "$log"; then
      cat "$log"
      echo "Expected failure log for $target to contain: $expected" >&2
      exit 1
    fi
  done
}

check_failure \
  "//test/fixtures/layering_check:foundation_consumer_violation_precompiled_modules" \
  "//test/fixtures/layering_check:foundation_consumer" \
  "Foundation"
check_failure "//test/fixtures/layering_check:layering_violation"
check_failure \
  "//test/fixtures/layering_check:layering_violation_explicit_modules" \
  "//test/fixtures/layering_check:layering_violation"
check_failure \
  "//test/fixtures/layering_check:layering_violation_explicit_modules_default_precompiled_modules" \
  "//test/fixtures/layering_check:layering_violation"
