#!/usr/bin/env bash

set -euo pipefail

bazel="${BAZEL:-bazel}"
log="$(mktemp "${TMPDIR:-/tmp}/layering_check_failure_test.XXXXXX")"
trap 'rm -f "$log"' EXIT

check_failure() {
  local target="$1"
  local expected_module="$2"
  local expected_label="${3:-$target}"

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

check_unused_failure() {
  local target="$1"
  local expected_module="${2:-DirectDependency}"

  if "$bazel" build "$target" \
    --features=swift.layering_check_unused_deps &>"$log"; then
    cat "$log"
    echo "Expected $target to fail to build" >&2
    exit 1
  fi

  for expected in \
    "Unused dependencies in" \
    "$target" \
    "$expected_module" \
    "Please remove the unused 'deps'"; do
    if ! grep -Fq "$expected" "$log"; then
      cat "$log"
      echo "Expected failure log for $target to contain: $expected" >&2
      exit 1
    fi
  done
}

# Targets named `shared_prefix.<n>` all live in one package, so a layering
# check that derives its scratch file from the text before the first dot would
# share it between them and, when they compile in parallel, read another
# target's imports. Workers run unsandboxed (Bazel's default) so they share the
# exec root, and each run uses a new `-D` so every target recompiles.
check_shared_prefix_success() {
  local targets=()
  for i in $(seq 0 15); do
    targets+=("//test/fixtures/layering_check:shared_prefix.$i")
  done

  for run in 1 2 3 4 5; do
    if ! "$bazel" build "${targets[@]}" \
      --features=swift.layering_check_unused_deps \
      --noworker_sandboxing \
      "--swiftcopt=-DSHARED_PREFIX_RUN_${run}_$$" &>"$log"; then
      cat "$log"
      echo "Expected the shared_prefix targets to build (run $run)" >&2
      exit 1
    fi
  done
}

check_shared_prefix_success
check_failure \
  "//test/fixtures/layering_check:foundation_consumer_violation_precompiled_modules" \
  "Foundation" \
  "//test/fixtures/layering_check:foundation_consumer"
check_failure \
  "//test/fixtures/layering_check:layering_violation" \
  "TransitiveDependency (//test/fixtures/layering_check:TransitiveDependency)"
check_failure \
  "//test/fixtures/layering_check:layering_violation_explicit_modules" \
  "TransitiveDependency" \
  "//test/fixtures/layering_check:layering_violation"
check_failure \
  "//test/fixtures/layering_check:layering_violation_explicit_modules_default_precompiled_modules" \
  "TransitiveDependency" \
  "//test/fixtures/layering_check:layering_violation"
check_unused_failure "//test/fixtures/layering_check:unused_dependency"
check_unused_failure "//test/fixtures/layering_check:unused_test_dependency"
