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
      --action_env=PATH
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
if [[ -n "${BUILDIFIER:-}" ]]; then
  FOUND_ISSUES="no"

  # buildifier supports BUILD/WORKSPACE/*.bzl files, this provides the args
  # to reuse in all the finds.
  FIND_ARGS=(
      \(
          -name BUILD
          -o
          -name WORKSPACE
          -o
          -name "*.bzl"
      \)
  )

  # Check for format issues?
  if [[ "${FORMAT:-yes}" == "yes" ]] ; then
    # bazelbuild/buildtools/issues/220 - diff doesn't include the file that needs updating
    if ! find . "${FIND_ARGS[@]}" -print | xargs buildifier -d > /dev/null 2>&1 ; then
      if [[ "${FOUND_ISSUES}" != "no" ]] ; then
        echo ""
      fi
      echo "ERROR: BUILD/.bzl file formatting issue(s):"
      echo ""
      # bazelbuild/buildtools/issues/329 - sed out the exit status lines.
      find . "${FIND_ARGS[@]}" -print -exec buildifier -v -d {} \; \
          2>&1 | sed -E -e '/^exit status 1$/d'
      echo ""
      echo "Please download the latest buildifier"
      echo "   https://github.com/bazelbuild/buildtools/releases"
      echo "and run it over the changed BUILD/.bzl files."
      FOUND_ISSUES="yes"
    fi
  fi

  # Check for lint issues?
  if [[ "${LINT:-yes}" == "yes" ]] ; then
    # NOTE: buildifier defaults to --mode=fix, so these lint runs also
    # reformat the files. But since this is on travis, that is fine.
    # https://github.com/bazelbuild/buildtools/issues/453
    if ! find . "${FIND_ARGS[@]}" -print | xargs buildifier --lint=warn > /dev/null 2>&1 ; then
      if [[ "${FOUND_ISSUES}" != "no" ]] ; then
        echo ""
      fi
      echo "ERROR: BUILD/.bzl lint issue(s):"
      echo ""
      # buildifier now exist with error if there are issues, so use `|| true`
      # to keep the script running.
      find . "${FIND_ARGS[@]}" -print | xargs buildifier --lint=warn || true
      echo ""
      echo "Please download the latest buildifier"
      echo "   https://github.com/bazelbuild/buildtools/releases"
      echo "and run it with --lint=(warn|fix) over the changed BUILD/.bzl files"
      echo "and make the edits as needed."
      FOUND_ISSUES="yes"
    fi
  fi

  # Anything?
  if [[ "${FOUND_ISSUES}" != "no" ]] ; then
    exit 1
  fi
fi
