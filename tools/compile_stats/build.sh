#!/bin/bash
#
# Copyright 2019 The Bazel Authors. All rights reserved.
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

set -euo pipefail

manifest="$(mktemp "${TMPDIR:-/tmp}/compile_stats_manifest.XXXXXX")"
trap "rm -f $manifest" EXIT

collect_stats_flags=(
  --features=swift.compile_stats
  --output_groups=swift_compile_stats
  --aspects=@build_bazel_rules_swift//swift:stats.bzl%collect_swift_compile_stats
)

# Build the desired targets, with stderr being output as normal.
bazel build "${collect_stats_flags[@]}" "$@"

# Build the targets *again*, this time with `--experimental_show_artifacts`.
# This should be a null build since we just built everything above. The reason
# we split this is because the artifact output also goes to stderr, so we'd have
# to either capture the whole thing or redirect it to `tee` with color/curses
# support disabled, which would be difficult for the user to read.
#
# A human-readable explanation of the code below:
#
# 1. Build the requested targets while collecting the stats outputs. Use the
#    `--experimental_show_artifacts` flag to get a scrapeable dump of the output
#    files at the end.
# 2. Pipe stderr into a `sed` command that ignores all lines before the line
#    "Build artifacts:", which signifies the beginning of the listing.
# 3. Pipe that into a `sed` command that ignores any lines that don't start with
#    ">>>" and strips that prefix off the ones that do. This is the list of
#    stats directories that were created for each built target.
# 4. Pass those directories into `find` to print just the filenames of the
#    contents of those directories.

bazel build --experimental_show_artifacts "${collect_stats_flags[@]}" "$@" \
    2>&1 > /dev/null \
    | sed -e '/Build artifacts:/,$!d' \
    | sed -e 's/^>>>//' -e 't' -e 'd' \
    | while read statsdir ; do
        find "$statsdir" -type f
      done > "$manifest"

# Run the report generating tool.
bazel run \
    --apple_platform_type=macos \
    @build_bazel_rules_swift//tools/compile_stats:stats_processor -- \
    "$manifest"
