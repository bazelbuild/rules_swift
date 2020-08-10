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

load("@rules_proto//proto:defs.bzl", "ProtoInfo")
load(":providers.bzl", "SwiftInfo", "SwiftProtoInfo")
load(
    ":swift_protoc_gen_aspect.bzl",
    "SwiftProtoCcInfo",
    "swift_protoc_gen_aspect",
)

def _swift_proto_library_impl(ctx):
    if len(ctx.attr.deps) != 1:
        fail(
            "You must list exactly one target in the deps attribute.",
            attr = "deps",
        )

    dep = ctx.attr.deps[0]
    proto_cc_info = dep[SwiftProtoCcInfo]
    cc_info = proto_cc_info.cc_info
    swift_info = dep[SwiftInfo]
    swift_proto_info = dep[SwiftProtoInfo]

    providers = [
        # Return the generated sources as the default outputs if the user builds
        # this target standalone (along with the direct .swiftmodules, to force
        # compilation). This lets users easily inspect those sources to
        # determine the interfaces of the generated protos, which have
        # previously been a bit difficult to find.
        DefaultInfo(
            files = depset(
                [
                    module.swift.swiftmodule
                    for module in swift_info.direct_modules
                ],
                transitive = [swift_proto_info.pbswift_files],
            ),
        ),
        # Repropagate the Swift* and Cc* providers that the aspect attached to
        # the `proto_library` dependency so that the modules and link libraries
        # are passed through correctly.
        cc_info,
        swift_info,
        # Repropagate the `SwiftProtoInfo` provider so that downstream
        # rules/aspects can access the sources if necessary. (This should
        # typically only be used for IDE support.)
        swift_proto_info,
    ]

    # Propagate a nested apple_common.Objc provider if present so that
    # apple_binary targets link correctly.
    if proto_cc_info.objc_info:
        providers.append(proto_cc_info.objc_info)

    return providers

swift_proto_library = rule(
    attrs = {
        "deps": attr.label_list(
            aspects = [swift_protoc_gen_aspect],
            doc = """\
Exactly one `proto_library` target (or any target that propagates a `proto`
provider) from which the Swift library should be generated.
""",
            providers = [ProtoInfo],
        ),
    },
    doc = """\
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

Note that the module name of the Swift library produced by this rule (if any) is
based on the name of the `proto_library` target, *not* the name of the
`swift_proto_library` target. In other words, if the following BUILD file were
located in `//my/pkg`, the target would create a Swift module named
`my_pkg_foo`:

```python
proto_library(
    name = "foo",
    srcs = ["foo.proto"],
)

swift_proto_library(
    name = "foo_swift",
    deps = [":foo"],
)
```

Because the Swift modules are generated from an aspect that is applied to the
`proto_library` targets, the module name and other compilation flags for the
resulting Swift modules cannot be changed.

#### Tip: Where to locate `swift_proto_library` targets

Convention is to put the `swift_proto_library` in the same `BUILD` file as the
`proto_library` it is generating for (just like all the other
`LANG_proto_library` rules). This lets anyone needing the protos in Swift share
the single rule as well as making it easier to realize what proto files are in
use in what contexts.

This is not a requirement, however, as it may not be possible for Bazel
workspaces that create `swift_proto_library` targets that depend on
`proto_library` targets from different repositories.

#### Tip: Avoid `import` only `.proto` files

Avoid creating a `.proto` file that just contains `import` directives of all the
other `.proto` files you need. While this does _group_ the protos into this new
target, it comes with some high costs. This causes the proto compiler to parse
all those files and invoke the generator for an otherwise empty source file.
That empty source file then has to get compiled, but it will have dependencies
on the full deps chain of the imports (recursively). The Swift compiler must
load all of these module dependencies, which can be fairly slow if there are
many of them, so this method of grouping via a `.proto` file actually ends up
creating build steps that slow down the build.

#### Tip: Resolving unused import warnings

If you see warnings like the following during your build:

```
path/file.proto: warning: Import other/path/file.proto but not used.
```

The proto compiler is letting you know that you have an `import` statement
loading a file from which nothing is used, so it is wasted work. The `import`
can be removed (in this case, `import other/path/file.proto` could be removed
from `path/file.proto`). These warnings can also mean that the `proto_library`
has `deps` that aren't needed. Removing those along with the `import`
statement(s) will speed up downstream Swift compilation actions, because it
prevents unused modules from being loaded by `swiftc`.
""",
    implementation = _swift_proto_library_impl,
)
