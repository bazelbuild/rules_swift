#!/bin/bash

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

set -eu

# ------------------------------------------------------------------------------
# Add the downloaded Swift toolchain to the path if it's requested. (It would be
# nice to do this as part of the install script instead, but then it only
# affects _that_ script.)
if [[ -n "${SWIFT_VERSION:-}" ]]; then
  export PATH="$(pwd)/.swift/swift-$SWIFT_VERSION-RELEASE-ubuntu14.04/usr/bin:$PATH"
fi

# ------------------------------------------------------------------------------
# Asked to do a bazel build.
if [[ -n "${BAZEL:-}" ]]; then
  # - Crank down the progress messages to not flood the travis log, but still
  #   provide some output so there is an indicator things aren't hung.
  # - "--test_output=errors" causes failures to report more completely since
  #   just getting the log file info isn't that useful on CI.
  #
  # Note also that BUILD_ARGS and TARGETS are intentionally used unquoted.
  # Since they are environment variables, they can't be Bash arrays, so we use
  # double-quoted strings to set them instead and just let them expand below.
  set -x
  BAZELRC_ARGS=("--bazelrc=.travis/bazelrc.${TRAVIS_OS_NAME}")
  ALL_BUILD_ARGS=(
      --show_progress_rate_limit=30.0
      --verbose_failures
  )
  if [[ -n "${BUILD_ARGS:-}" ]]; then
    ALL_BUILD_ARGS+=(${BUILD_ARGS})
  fi

  ALL_TEST_ARGS=(--test_output=errors)
  if [[ -n "${TAGS:-}" ]]; then
    ALL_TEST_ARGS+=("--test_tag_filters=${TAGS}")
  fi

  bazel "${BAZELRC_ARGS[@]}" build "${ALL_BUILD_ARGS[@]}" -- ${TARGETS}
  bazel "${BAZELRC_ARGS[@]}" test "${ALL_BUILD_ARGS[@]}" "${ALL_TEST_ARGS[@]}" -- ${TARGETS}
  set +x
fi

# ------------------------------------------------------------------------------
# Asked to do a buildifier run.
if [[ -n "${BUILDIFER:-}" ]]; then
  # bazelbuild/buildtools/issues/220 - diff doesn't include the file that needs
  # updating
  # bazelbuild/buildtools/issues/221 - the exit status is always zero.
  if [[ -n "$(find . -name BUILD -print | xargs buildifier -v -d)" ]]; then
    echo "ERROR: BUILD file formatting issue(s)"
    find . -name BUILD -print -exec buildifier -v -d {} \;
    exit 1
  fi
fi
