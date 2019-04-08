#!/bin/bash
#
# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# SYNOPSIS
#   Invokes a Swift tool, adding custom pre- and post-invocation behavior
#   needed by the Bazel build rules.
#
#   This script recognizes special arguments of the form
#   `-Xwrapped-swift=<arg>` to enable special behaviors. These arguments must
#   be passed directly on the command line; for performance reasons this script
#   does not process params files. Arguments of this form are consumed entirely
#   by this wrapper and are not passed down to the Swift tool (however, they
#   may add normal arguments that would be passed).
#
# USAGE
#   swift_wrapper <executable> <arguments...>
#
# ARGUMENTS
#   executable: The executable to invoke. This should be a tool in the Swift
#       toolchain, or a similar invocation (like `xcrun` followed by a Swift
#       tool).
#   arguments...: Arguments that are either processed by the wrapper or passed
#       directly to the underlying Swift tool.
#
#   The following wrapper-specific arguments are supported:
#
#   -Xwrapped-swift=-ephemeral-module-cache
#       When specified, the wrapper will create a new temporary directory, pass
#       that to the Swift compiler using `-module-cache-path`, and then delete
#       the directory afterwards. This should resolve issues where the module
#       cache state is not refreshed correctly in all situations, which
#       sometimes results in hard-to-diagnose crashes in `swiftc`.

set -eu

# SYNOPSIS
#   Rewrites special arguments in the given argument string, echoing the result.
#
# USAGE
#   rewrite_argument <argument>
function rewrite_argument {
  case "$1" in
  -Xwrapped-swift=-ephemeral-module-cache)
    MODULE_CACHE_DIR="$(mktemp -d "${TMPDIR%/}/wrapped_swift_module_cache.XXXXXXXXXX")"
    echo "-module-cache-path $MODULE_CACHE_DIR"
    ;;
  -fmodule-map-file=[^/]*)
    # TODO(allevato): Remove this workaround once this patch is in a release:
    # https://github.com/apple/swift-lldb/pull/1369
    MODULE_MAP_FILE="${1#-fmodule-map-file=}"
    echo "-fmodule-map-file=$PWD/$MODULE_MAP_FILE"
    ;;
  *)
    echo "$1"
    ;;
  esac
}

# SYNOPSIS
#   Rewrites special arguments in the given params file, if any.
#   If there were no substitutions to be made, the original path is echoed back
#   out; otherwise, this function echoes the path to a temporary file
#   containing the rewritten file.
#
# USAGE
#   rewrite_params_file <path>
function rewrite_params_file {
  PARAMSFILE="$1"
  if grep -qe '-fmodule-map-file=' "$PARAMSFILE" ; then
    NEWFILE="$(mktemp "${TMPDIR%/}/swift_wrapper_params.XXXXXXXXXX")"
    # TODO(allevato): Remove this workaround once this patch is in a release:
    # https://github.com/apple/swift-lldb/pull/1369
    sed \
        -e "s#-fmodule-map-file=\([^/]\)#-fmodule-map-file=$PWD/\1#g" \
        "$PARAMSFILE" > "$NEWFILE"
    echo "$NEWFILE"
  else
    # There were no placeholders to substitute, so just return the original
    # file.
    echo "$PARAMSFILE"
  fi
}

# Called when the wrapper exits (normally or abnormally) to clean up any
# temporary state.
function cleanup {
  if [[ -n "$MODULE_CACHE_DIR" ]] ; then
    rm -rf "$MODULE_CACHE_DIR"
  fi
  if [[ ${#TEMPFILES[@]} -ne 0 ]] ; then
    rm "${TEMPFILES[@]}"
  fi
}
# If any temporary files are created (like rewritten response files), clean
# them up when the script exits.
TEMPFILES=()

trap cleanup EXIT

TOOLNAME="$1"
shift

TMPDIR="${TMPDIR:-/tmp}"
MODULE_CACHE_DIR=
USE_WORKER=0

# Process the argument list.
ARGS=()
for ARG in "$@" ; do
  case "$ARG" in
  @*)
    PARAMSFILE="${ARG:1}"
    NEWFILE=$(rewrite_params_file "$PARAMSFILE")
    if [[ "$PARAMSFILE" != "$NEWFILE" ]] ; then
      TEMPFILES+=("$NEWFILE")
    fi
    ARGS+=("@$NEWFILE")
    ;;
  --persistent_worker)
    USE_WORKER=1
    ;;
  *)
    ARGS+=($(rewrite_argument "$ARG"))
    ;;
  esac
done

if [[ "$USE_WORKER" -eq 1 ]] ; then
  # This assumes that the worker executable is passed as a tool input to
  # run_toolchain_swift_action.
  SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
  "$SCRIPTDIR/../worker/worker" "$TOOLNAME" "${ARGS[@]}"
else
  # Invoke the underlying command with the modified arguments. We don't use
  # `exec` here beause we need the cleanup trap to run after execution.
  "$TOOLNAME" "${ARGS[@]}"
fi
