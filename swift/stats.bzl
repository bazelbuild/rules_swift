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

"""An aspect that collects compilation timing statistics."""

load("@build_bazel_rules_swift//swift/internal:utils.bzl", "get_output_groups")

def _collect_swift_compile_stats_impl(target, aspect_ctx):
    output_groups = target[OutputGroupInfo]

    deps = getattr(aspect_ctx.rule.attr, "deps", [])
    merged_stats = get_output_groups(deps, "swift_compile_stats")
    direct_stats = getattr(output_groups, "swift_compile_stats_direct", None)
    if direct_stats:
        merged_stats.append(direct_stats)

    return [OutputGroupInfo(swift_compile_stats = depset(transitive = merged_stats))]

collect_swift_compile_stats = aspect(
    attr_aspects = ["deps"],
    doc = """
Collects compilation statistics reports from the entire build graph.

This aspect is intended to be used from the command line to profile the Swift compiler during a
build. It needs to be combined with the `swift.compile_stats` feature that asks the compiler to
write out the statistics and a request for the `swift_compile_stats` output group so that the
files are available at the end of the build:

```
bazel build //your/swift:target \
    --features=swift.compile_stats \
    --output_groups=swift_compile_stats \
    --aspects=@build_bazel_rules_swift//swift:stats.bzl%collect_swift_compile_stats
```

Since this command is a bit of a mouthful, we've provided a helper script in the tools directory
that wraps this up:

```
.../tools/compile_stats/build.sh <args to pass to Bazel>
```
""",
    implementation = _collect_swift_compile_stats_impl,
)
