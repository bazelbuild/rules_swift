#!/usr/bin/env bash

# Runs a `swift_toolchain_tool` target with the given arguments and checks its
# output against an extended regular expression. With `--output`, checks the
# contents of a file instead, such as the output of a genrule that ran the
# tool.
#
# Usage: run_tool_test.sh <rlocationpath> <regex> [<arg>...]
#        run_tool_test.sh --output <rlocationpath> <regex>

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

usage() {
  echo >&2 "Usage: ${0} <rlocationpath> <regex> [<arg>...]"
  echo >&2 "       ${0} --output <rlocationpath> <regex>"
  exit 1
}

mode=run
if [[ "${1:-}" == "--output" ]]; then
  mode=output
  shift
fi
if [[ ${#} -lt 2 ]]; then
  usage
fi

rlocationpath="${1}"
expected_regex="${2}"
shift 2

if [[ "${mode}" == "output" ]]; then
  if [[ ${#} -ne 0 ]]; then
    usage
  fi
  file="$(rlocation "${rlocationpath}")" || true
  if [[ -z "${file}" || ! -f "${file}" ]]; then
    echo >&2 "ERROR: cannot locate '${rlocationpath}' in runfiles"
    exit 1
  fi
  output="$(<"${file}")"
  description="the contents of '${rlocationpath}'"
else
  # The rule writes `<name>.bat` on Windows and `<name>` elsewhere.
  tool=""
  for candidate in "${rlocationpath}" "${rlocationpath}.bat"; do
    tool="$(rlocation "${candidate}")" || true
    if [[ -n "${tool}" && -f "${tool}" ]]; then
      break
    fi
    tool=""
  done
  if [[ -z "${tool}" ]]; then
    echo >&2 "ERROR: cannot locate '${rlocationpath}' or" \
      "'${rlocationpath}.bat' in runfiles"
    exit 1
  fi

  if ! output="$("${tool}" "${@}" 2>&1)"; then
    echo >&2 "${output}"
    echo >&2 "ERROR: '${rlocationpath} ${*}' failed"
    exit 1
  fi
  description="the output of '${rlocationpath} ${*}'"
fi
echo "${output}"

if ! grep -Eq -- "${expected_regex}" <<<"${output}"; then
  echo >&2 "ERROR: expected ${description} to match '${expected_regex}'"
  exit 1
fi
