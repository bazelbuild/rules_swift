# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""
Defines a rule that generates a Swift library from protocol buffer sources.
"""

load(
    "@bazel_skylib//lib:dicts.bzl",
    "dicts",
)
load(
    "@rules_proto//proto:defs.bzl",
    "ProtoInfo",
)
load(
    "//proto:swift_proto_utils.bzl",
    "generate_module_mappings",
    "generate_swift_protos_for_target",
    "compile_swift_protos_for_target",
)
load(
    "//swift:swift.bzl",
    "SwiftProtoCompilerInfo",
    "swift_common",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:attrs.bzl",
    "swift_deps_attr",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)

# Private

def _get_module_name(attr, target_label):
    """Gets the module name from the given attributes and target label.

    Uses the module name from the attribute if provided,
    or failing this, falls back to the derived module name.
    """
    module_name = attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(target_label)
    return module_name

# Rule

def _swift_proto_library_impl(ctx):

    # Get the module name and generate the module mappings:
    module_name = _get_module_name(ctx.attr, ctx.label)
    proto_infos = [d[ProtoInfo] for d in ctx.attr.protos]
    deps = getattr(ctx.attr, "deps", [])

    # Generate the module mappings:
    module_mappings = generate_module_mappings(
        module_name,
        proto_infos,
        deps,
    )

    # Compile the protos to source files:
    compiler_deps, generated_swift_srcs = generate_swift_protos_for_target(
        ctx,
        proto_infos,
        module_mappings,
        ctx.attr.compilers,
        ctx.attr.additional_compiler_info,
    )

    # Compile the source files to a module:
    direct_output_group_info, direct_proto_cc_info, direct_swift_info, direct_swift_proto_info = compile_swift_protos_for_target(
        ctx,
        ctx.attr,
        ctx.label,
        module_name,
        module_mappings,
        generated_swift_srcs,
        compiler_deps + ctx.attr.deps + ctx.attr.additional_compiler_deps,
    )

    return [
        DefaultInfo(
            files = depset(
                [
                    module.swift.swiftmodule
                    for module in direct_swift_info.direct_modules
                ],
                transitive = [direct_swift_proto_info.pbswift_files],
            ),
        ),
        direct_output_group_info,
        direct_proto_cc_info.cc_info,
        direct_proto_cc_info.objc_info,
        direct_swift_info,
        direct_swift_proto_info,
    ]

swift_proto_library = rule(
    attrs = dicts.add(
        swift_common.library_rule_attrs(
            additional_deps_aspects = [
                swift_clang_module_aspect,
            ],
            requires_srcs = False,
        ),
        {
            "protos": attr.label_list(
                doc = """\
A list of `proto_library` targets (or targets producing `ProtoInfo`),
from which the Swift source files should be generated.
""",
                providers = [ProtoInfo],
            ),
            "compilers": attr.label_list(
                default = ["//proto/compilers:swift_proto"],
                doc = """\
One or more `swift_proto_compiler` targets (or targets producing `SwiftProtoCompilerInfo`),
from which the Swift protos will be generated.
""",
                providers = [SwiftProtoCompilerInfo],
            ),
            "additional_compiler_deps": swift_deps_attr(
                aspects = [
                    swift_clang_module_aspect,
                ],
                default = [],
                doc = """\
List of additional dependencies required by the generated Swift code at compile time, 
whose SwiftProtoInfo will be ignored.
""",
            ),
            "additional_compiler_info": attr.string_dict(
                default = {},
                doc = """\
Dictionary of additional information passed to the compiler targets.
See the documentation of the respective compiler rules for more information
on which fields are accepted and how they are used.
""",
            ),
        },
    ),
    doc = """\
Generates a Swift static library from one or more targets producing `ProtoInfo`.

```python
load("@rules_proto//proto:defs.bzl", "proto_library")
load("//proto:proto.bzl", "swift_proto_library")

proto_library(
    name = "foo",
    srcs = ["foo.proto"],
)

swift_proto_library(
    name = "foo_swift",
    protos = [":foo"],
)
```

If your protos depend on protos from other targets, add dependencies between the 
swift_proto_library targets which mirror the dependencies between the proto targets.

```python
load("@rules_proto//proto:defs.bzl", "proto_library")
load("//proto:proto.bzl", "swift_proto_library")

proto_library(
    name = "bar",
    srcs = ["bar.proto"],
    deps = [":foo"],
)

swift_proto_library(
    name = "bar_swift",
    protos = [":bar"],
    deps = [":foo_swift"],
)
```
""",
    fragments = ["cpp"],
    implementation = _swift_proto_library_impl,
)
