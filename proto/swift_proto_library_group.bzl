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
    "generate_module_mappings",
    "compile_protos_for_target",
)
load(
    "//swift:swift.bzl",
    "SwiftInfo",
    "SwiftProtoCompilerInfo",
    "SwiftProtoInfo",
    "swift_common",
)

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)

# _swift_proto_library_group_aspect

def _swift_proto_library_group_aspect_impl(target, aspect_ctx):

    # Get the module name and generate the module mappings:
    module_name = swift_common.derive_module_name(target.label)
    proto_infos = [target[ProtoInfo]]
    module_mappings = generate_module_mappings(
        module_name,
        proto_infos,
        getattr(aspect_ctx.rule.attr, "deps", []),
    )

    # Compile the protos for the target:
    _, output_group_info, cc_info, swift_info, swift_proto_info, objc_info = compile_protos_for_target(
        aspect_ctx,
        aspect_ctx.rule.attr,
        target.label,
        module_name,
        proto_infos,
        module_mappings,
        aspect_ctx.attr._compilers,
    )

    return [
        output_group_info,
        cc_info,
        swift_info,
        swift_proto_info,
        objc_info
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

    # Compile each target into a different swift module:
    cc_infos = []
    swift_infos = []
    swift_proto_infos = []
    objc_infos = []
    for proto_target in ctx.attr.protos:
        if CcInfo in proto_target:
            cc_infos.append(proto_target[CcInfo])
        if SwiftInfo in proto_target:
            swift_infos.append(proto_target[SwiftInfo])
        if SwiftProtoInfo in proto_target:
            swift_proto_infos.append(proto_target[SwiftProtoInfo])
        if apple_common.Objc in proto_target:
            objc_infos.append(proto_target[apple_common.Objc])

    # Merge the providers:
    cc_info = cc_common.merge_cc_infos(
        direct_cc_infos = cc_infos
    )
    swift_info = swift_common.create_swift_info(
        swift_infos = swift_infos,
    )
    objc_info = apple_common.new_objc_provider(
        providers = objc_infos,
    )
    direct_pbswift_files = []
    module_mappings = []
    for swift_proto_info in swift_proto_infos:
        direct_pbswift_files.extend(swift_proto_info.direct_pbswift_files)
        module_mappings.extend(swift_proto_info.module_mappings)
    swift_proto_info = SwiftProtoInfo(
        direct_pbswift_files = direct_pbswift_files,
        module_mappings = module_mappings,
        pbswift_files = depset(direct_pbswift_files),
    )
    default_info = DefaultInfo(
        files = depset(
            direct = [
                module.swift.swiftmodule
                for module in swift_info.direct_modules
            ],
            transitive = [swift_proto_info.pbswift_files],
        )
    )
    
    return [
        default_info,
        cc_info,
        swift_info,
        swift_proto_info,
        objc_info
    ]

swift_proto_library_group = rule(
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
                aspects = [_swift_proto_library_group_aspect],
                providers = [ProtoInfo],
            ),
        },
    ),
    fragments = ["cpp"],
    implementation = _swift_proto_library_group_impl,
)