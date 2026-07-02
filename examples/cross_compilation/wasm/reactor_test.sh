#!/usr/bin/env bash

# Executes the Swift reactor under wasmtime and asserts on the value Swift
# computes: `greeting_length` returns the UTF-8 length of
# "Hello from Swift, WebAssembly!" (30).

set -euo pipefail

wasmtime="$TEST_SRCDIR/$1"
reactor="$TEST_SRCDIR/$2"

actual="$("$wasmtime" run --invoke greeting_length "$reactor" 2>/dev/null)"
if [[ "$actual" != "30" ]]; then
  echo "error: expected greeting_length to return 30, got: $actual" >&2
  exit 1
fi
