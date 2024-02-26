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
Defines a rule that generates Swift libraries from protocol buffer sources.
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
    "SwiftProtoCcInfo",
    "generate_module_mappings",
    "generate_swift_protos_for_target",
    "compile_swift_protos_for_target",
)
load(
    "//swift:swift.bzl",
    "SwiftInfo",
    "SwiftProtoCompilerInfo",
    "SwiftProtoInfo",
    "swift_common",
)

# _swift_proto_library_group_aspect

def _swift_proto_library_group_aspect_impl(target, aspect_ctx):

    # Get the module name and generate the module mappings:
    module_name = swift_common.derive_module_name(target.label)
    proto_infos = [target[ProtoInfo]]

    # Generate the module mappings:
    module_mappings = generate_module_mappings(
        module_name,
        proto_infos,
        aspect_ctx.rule.attr.deps,
    )

    # Compile the protos to source files:
    compiler_deps, generated_swift_srcs = generate_swift_protos_for_target(
        aspect_ctx,
        proto_infos,
        module_mappings,
        aspect_ctx.attr._compilers,
    )

    # Compile the source files to a module:
    direct_output_group_info, direct_proto_cc_info, direct_swift_info, direct_swift_proto_info = compile_swift_protos_for_target(
        aspect_ctx,
        aspect_ctx.rule.attr,
        target.label,
        module_name,
        module_mappings,
        generated_swift_srcs,
        compiler_deps + aspect_ctx.rule.attr.deps,
    )

    return [
        direct_output_group_info, 
        direct_proto_cc_info, 
        direct_swift_info,
        direct_swift_proto_info,
    ]

_swift_proto_library_group_aspect = aspect(
    attr_aspects = ["deps"],
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        {
            "_compilers": attr.label_list(
                default = ["//proto/compilers:swift_proto"],
                doc = """\
One or more `swift_proto_compiler` targets (or targets producing `SwiftProtoCompilerInfo`),
from which the Swift protos will be generated.
""",
                providers = [SwiftProtoCompilerInfo],
            ),
        }
    ),
    doc = """\
    Gathers all of the transitive ProtoInfo providers along the deps attribute
    """,
    fragments = ["cpp"],
    implementation = _swift_proto_library_group_aspect_impl,
)

# swift_proto_library_group

def _swift_proto_library_group_impl(ctx):
    if len(ctx.attr.deps) != 1:
        fail(
            "You must list exactly one target in the deps attribute.",
            attr = "deps",
        )

    dep = ctx.attr.deps[0]
    proto_cc_info = dep[SwiftProtoCcInfo]
    swift_info = dep[SwiftInfo]
    swift_proto_info = dep[SwiftProtoInfo]

    return [
        DefaultInfo(
            files = depset(
                [
                    module.swift.swiftmodule
                    for module in swift_info.direct_modules
                ],
                transitive = [swift_proto_info.pbswift_files],
            ),
        ),
        proto_cc_info.cc_info,
        proto_cc_info.objc_info,
        swift_info,
        swift_proto_info,
    ]

swift_proto_library_group = rule(
    attrs = {
        "deps": attr.label_list(
            aspects = [_swift_proto_library_group_aspect],
            doc = """\
Exactly one `proto_library` target (or target producing `ProtoInfo`),
from which the Swift source files should be generated.
""",
            providers = [ProtoInfo],
        ),
    },
    fragments = ["cpp"],
    implementation = _swift_proto_library_group_impl,
)