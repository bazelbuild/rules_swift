#!/usr/bin/env bash
#
# `bazel run @rules_swift//tools/explicit_modules:scan -- --help`
#

set -euo pipefail

script=$PWD/$1
shift

cd "$BUILD_WORKING_DIRECTORY"

exec "$script" "$@"
