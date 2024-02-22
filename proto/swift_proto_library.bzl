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
    "//proto:swift_proto_common.bzl",
    "swift_proto_common",
)
load(
    "//swift:swift.bzl",
    "SwiftInfo",
    "SwiftToolchainInfo",
    "swift_common",
)
load(
    "//swift/internal:attrs.bzl",
    "swift_deps_attr",
)
load(
    "//swift/internal:compiling.bzl",
    "output_groups_from_other_compilation_outputs",
)
load(
    "//swift/internal:linking.bzl",
    "new_objc_provider",
)
load(
    "//swift/internal:providers.bzl",
    "SwiftProtoCompilerInfo",
    "SwiftProtoInfo",
)
load(
    "//swift/internal:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(
    "//swift/internal:utils.bzl",
    "compact",
    "get_providers",
    "include_developer_search_paths",
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

def _get_module_mappings(attr, module_name):
    """Gets module mappings from the ProtoInfo and SwiftProtoInfo providers.
    """

    # Collect the direct proto source files from the proto deps and build the module mapping:
    proto_deps = getattr(attr, "protos", [])
    direct_proto_file_paths = []
    for proto_dep in proto_deps:
        proto_info = proto_dep[ProtoInfo]
        proto_file_paths = [
            swift_proto_common.proto_path(proto_src, proto_info)
            for proto_src in proto_info.check_deps_sources.to_list()
        ]
        direct_proto_file_paths.extend(proto_file_paths)
    module_mapping = struct(
        module_name = module_name,
        proto_file_paths = direct_proto_file_paths,
    )

    # Collect the transitive module mappings:
    deps = getattr(attr, "deps", [])
    transitive_module_mappings = []
    for dep in deps:
        if not SwiftProtoInfo in dep:
            continue
        transitive_module_mappings.extend(dep[SwiftProtoInfo].module_mappings)

    # Create a list combining the direct + transitive module mappings:
    return [module_mapping] + transitive_module_mappings

# Rule

def _swift_proto_library_impl(ctx):
    # Extract the swift toolchain and configure the features:
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    # Get the module name and gather the depset of imports and module names:
    module_name = _get_module_name(ctx.attr, ctx.label)
    module_mappings = _get_module_mappings(ctx.attr, module_name)

    # Use the proto compiler to compile the swift sources for the proto deps:
    compiler_deps = [d for d in ctx.attr.additional_compiler_deps]
    generated_swift_srcs = []
    for swift_proto_compiler_target in ctx.attr.compilers:
        swift_proto_compiler_info = swift_proto_compiler_target[SwiftProtoCompilerInfo]
        compiler_deps.extend(swift_proto_compiler_info.compiler_deps)
        generated_swift_srcs.extend(swift_proto_compiler_info.compile(
            ctx,
            swift_proto_compiler_info = swift_proto_compiler_info,
            additional_compiler_info = ctx.attr.additional_compiler_info,
            proto_infos = [d[ProtoInfo] for d in ctx.attr.protos],
            module_mappings = module_mappings,
        ))

    # Collect the dependencies for the compile action:
    deps = ctx.attr.deps + compiler_deps

    # Compile the generated Swift source files as a module:
    include_dev_srch_paths = include_developer_search_paths(ctx)
    module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        copts = ["-parse-as-library"],
        deps = deps,
        feature_configuration = feature_configuration,
        include_dev_srch_paths = include_dev_srch_paths,
        module_name = module_name,
        package_name = None,
        srcs = generated_swift_srcs,
        swift_toolchain = swift_toolchain,
        target_name = ctx.label.name,
        workspace_name = ctx.workspace_name,
    )

    # Create the linking context from the compilation outputs:
    linking_context, linking_output = (
        swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            compilation_outputs = cc_compilation_outputs,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        )
    )

    # Create the providers:
    providers = [
        DefaultInfo(
            files = depset(compact([
                module_context.swift.swiftdoc,
                module_context.swift.swiftinterface,
                module_context.swift.swiftmodule,
                module_context.swift.swiftsourceinfo,
                linking_output.library_to_link.static_library,
                linking_output.library_to_link.pic_static_library,
            ])),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        OutputGroupInfo(**output_groups_from_other_compilation_outputs(
            other_compilation_outputs = other_compilation_outputs,
        )),
        CcInfo(
            compilation_context = module_context.clang.compilation_context,
            linking_context = linking_context,
        ),
        swift_common.create_swift_info(
            modules = [module_context],
            swift_infos = get_providers(deps, SwiftInfo),
        ),
        SwiftProtoInfo(
            module_name = module_name,
            module_mappings = module_mappings,
            direct_pbswift_files = generated_swift_srcs,
            pbswift_files = depset(
                direct = generated_swift_srcs,
                transitive = [dep[SwiftProtoInfo].pbswift_files for dep in deps if SwiftProtoInfo in dep],
            ),
        ),
    ]

    # Propagate an `apple_common.Objc` provider with linking info about the
    # library so that linking with Apple Starlark APIs/rules works correctly.
    # TODO(b/171413861): This can be removed when the Obj-C rules are migrated
    # to use `CcLinkingContext`.
    providers.append(new_objc_provider(
        additional_objc_infos = (
            swift_toolchain.implicit_deps_providers.objc_infos
        ),
        deps = deps,
        feature_configuration = feature_configuration,
        is_test = ctx.attr.testonly,
        module_context = module_context,
        libraries_to_link = [linking_output.library_to_link],
        swift_toolchain = swift_toolchain,
    ))

    return providers

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
One or more `swift_proto_compiler` target (or targets producing `SwiftProtoCompilerInfo`),
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
