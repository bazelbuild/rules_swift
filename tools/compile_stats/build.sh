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

bazel build \
    --features=swift.compile_stats \
    --output_groups=swift_compile_stats \
    --aspects=@build_bazel_rules_swift//swift:stats.bzl%collect_swift_compile_stats \
    --experimental_show_artifacts \
    "$@" \
    2>&1 > /dev/null \
    | sed -e '/Build artifacts:/,$!d' \
    | sed -e 's/^>>>//' -e 't' -e 'd' \
    | xargs -I{} find {} -type f
