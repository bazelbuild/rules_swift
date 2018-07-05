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

"""A rule that generates a Swift library from protocol buffer sources."""

load(":providers.bzl", "SwiftInfo")
load(":swift_protoc_gen_aspect.bzl", "swift_protoc_gen_aspect")

def _swift_proto_library_impl(ctx):
    if len(ctx.attr.deps) != 1:
        fail("You must list exactly one target in the deps attribute.", attr = "deps")

    dep = ctx.attr.deps[0]
    swift_info = dep[SwiftInfo]

    # If the proto_library dependency has srcs, then the Swift compile actions
    # produce a library and module for that target; doing so causes all the other
    # dependencies' libraries/modules to also be built, so it's sufficient to
    # just output those direct files. If the proto_library dependency only has
    # deps, however, no Swift compile actions are registered for *this* target, so
    # in order for it to build anything, we must list the transitive outputs as
    # our outputs. This has the effect of dumping a potentially large number of
    # files at the end of the build log, if the proto dependency tree is large,
    # but otherwise it's harmless.
    if swift_info.direct_libraries and swift_info.direct_swiftmodules:
        outputs = depset(
            direct = swift_info.direct_libraries + swift_info.direct_swiftmodules,
        )
    else:
        outputs = depset(transitive = [
            swift_info.transitive_libraries,
            swift_info.transitive_swiftmodules,
        ])

    providers = [DefaultInfo(files = outputs), swift_info]

    # Repropagate the apple_common.Objc provider if present so that apple_binary
    # targets link correctly.
    if apple_common.Objc in dep:
        providers.append(dep[apple_common.Objc])

    return providers

swift_proto_library = rule(
    attrs = {
        "deps": attr.label_list(
            aspects = [swift_protoc_gen_aspect],
            doc = """
Exactly one `proto_library` target (or any target that propagates a `proto`
provider) from which the Swift library should be generated.
""",
            providers = ["proto"],
        ),
    },
    doc = """
Generates a Swift library from protocol buffer sources.

There should be one `swift_proto_library` for any `proto_library` that you wish
to depend on. A target based on this rule can be used as a dependency anywhere
that a `swift_library` can be used.

A `swift_proto_library` target only creates a Swift module if the
`proto_library` on which it depends has a non-empty `srcs` attribute. If the
`proto_library` does not contain `srcs`, then no module is produced, but the
`swift_proto_library` still propagates the modules of its non-empty dependencies
so that those generated protos can be used by depending on the
`swift_proto_library` of the "collector" target.

Convention is to put the `swift_proto_library` in the same `BUILD` file as
the `proto_library` it is generating for (just like all the other
`LANG_proto_library` rules). This lets anyone needing the protos in Swift
share the single rule as well as making it easier to realize what proto
files are in use in what contexts.

Note that the module name of the Swift library produced by this rule (if any)
is based on the name of the `proto_library` target, *not* the name of the
`swift_proto_library` target. In other words, if the following BUILD file were
located in `//my/pkg`, the target would create a Swift module named
`my_pkg_foo`:

```
proto_library(
    name = "foo",
    srcs = ["foo.proto"],
)

swift_proto_library(
    name = "foo_swift",
    deps = [":foo"],
)
```
""",
    implementation = _swift_proto_library_impl,
)
