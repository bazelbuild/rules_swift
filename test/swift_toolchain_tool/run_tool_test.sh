#!/usr/bin/env bash

# Runs a `swift_toolchain_tool` target with the given arguments and checks its
# output against an extended regular expression.
#
# Usage: run_tool_test.sh <rlocationpath> <regex> [<arg>...]

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -o errexit -o nounset -o pipefail

if [[ ${#} -lt 2 ]]; then
  echo >&2 "Usage: ${0} <rlocationpath> <regex> [<arg>...]"
  exit 1
fi

tool_rlocationpath="${1}"
expected_regex="${2}"
shift 2

tool="$(rlocation "${tool_rlocationpath}")" || true
if [[ -z "${tool}" || ! -x "${tool}" ]]; then
  echo >&2 "ERROR: cannot locate '${tool_rlocationpath}' in runfiles"
  exit 1
fi

if ! output="$("${tool}" "${@}" 2>&1)"; then
  echo >&2 "${output}"
  echo >&2 "ERROR: '${tool_rlocationpath} ${*}' failed"
  exit 1
fi
echo "${output}"

if ! grep -Eq -- "${expected_regex}" <<<"${output}"; then
  echo >&2 "ERROR: expected the output above to match '${expected_regex}'"
  exit 1
fi
