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
    "SwiftInfo",
    "SwiftProtoInfo",
    "SwiftToolchainInfo",
)
load(
    "//swift/internal:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(
    "//swift/internal:swift_common.bzl",
    "swift_common",
)
load(
    "//swift/internal:utils.bzl",
    "compact",
    "get_providers",
)
load(
    ":swift_proto_compiler.bzl",
    "SwiftProtoCompilerInfo",
)
load(
    ":swift_proto_utils.bzl",
    "proto_path",
)

# Provider

SwiftProtoImportInfo = provider(
    doc = """
    Information aggregated by the Swift proto library aspect.
    """,
    fields = {
        "imports": "Depset of proto source files from the ProtoInfo providers in the protos attributes of swift_proto_library dependencies.",
    },
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

def _get_imports(attr, module_name):
    """Creates a depset of proto sources, ProtoInfo providers, and module names.

    The direct dependencies come from the protos attribute,
    and the transitive dependencies come from an aspect over the deps attribute,
    which extracts those same direct dependencies from the dependencies respective
    protos attributes.
    """

    # Collect the direct proto source files from the proto deps:
    proto_deps = getattr(attr, "protos", [])
    direct_imports = dict()
    for proto_dep in proto_deps:
        for proto_src in proto_dep[ProtoInfo].check_deps_sources.to_list():
            path = proto_path(proto_src, proto_dep[ProtoInfo])
            direct_imports["{}={}".format(path, module_name)] = True

    # Collect the transitive proto source files from the aspect-augmented deps:
    deps = getattr(attr, "deps", [])
    transitive_imports = [
        dep[SwiftProtoImportInfo].imports
        for dep in deps
        if SwiftProtoImportInfo in dep
    ]

    # Create a depset of the direct + transitive proto imports:
    return depset(direct = direct_imports.keys(), transitive = transitive_imports)

# Aspect

def _swift_proto_library_aspect_impl(target, aspect_ctx):
    module_name = _get_module_name(aspect_ctx.rule.attr, target.label)
    imports = _get_imports(aspect_ctx.rule.attr, module_name)
    return [SwiftProtoImportInfo(imports = imports)]

_swift_proto_library_aspect = aspect(
    _swift_proto_library_aspect_impl,
    attr_aspects = [
        "deps",
    ],
    doc = """\
    Traverses the deps attributes of the swift_proto_library targets,
    and creates a depset from their respective protos attributes as well as their
    module names.
    """,
)

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
    imports = _get_imports(ctx.attr, module_name)

    # Use the proto compiler to compile the swift sources for the proto deps:
    compiler_deps = [d for d in ctx.attr.compiler_deps]
    generated_swift_srcs = []
    for swift_proto_compiler_target in ctx.attr.compilers:
        swift_proto_compiler_info = swift_proto_compiler_target[SwiftProtoCompilerInfo]
        compiler_deps.extend(swift_proto_compiler_info.deps)
        generated_swift_srcs.extend(swift_proto_compiler_info.compile(
            ctx,
            swift_proto_compiler_info = swift_proto_compiler_info,
            additional_plugin_options = ctx.attr.additional_plugin_options,
            proto_infos = [d[ProtoInfo] for d in ctx.attr.protos],
            imports = imports,
        ))

    # Collect the dependencies for the compile action:
    deps = ctx.attr.deps + compiler_deps

    # Compile the generated Swift source files as a module:
    module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
        actions = ctx.actions,
        copts = ["-parse-as-library"],
        deps = deps,
        feature_configuration = feature_configuration,
        is_test = ctx.attr.testonly,
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
            is_test = ctx.attr.testonly,
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
            generated_swift_srcs = generated_swift_srcs,
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
                _swift_proto_library_aspect,
                swift_clang_module_aspect,
            ],
            requires_srcs = False,
        ),
        {
            "protos": attr.label_list(
                doc = """\
                Exactly one `proto_library` target from which the Swift library should be generated.
                """,
                providers = [ProtoInfo],
            ),
            "compiler_deps": swift_deps_attr(
                aspects = [
                    swift_clang_module_aspect,
                ],
                default = [],
                doc = """\
                A list of targets that are dependencies of the target being built, which will be
                linked into that target, but will be ignored by the proto compiler.
                """,
            ),
            "compilers": attr.label_list(
                default = ["//proto/compilers:swift_proto"],
                providers = [SwiftProtoCompilerInfo],
            ),
            "additional_plugin_options": attr.string_dict(
                default = {},
                doc = """\
                Dictionary of additional proto compiler plugin options for this target.
                See the documentation of plugin_options on swift_proto_compiler for more information.
                """,
            ),
        },
    ),
    doc = """\
    Generates a Swift library from protocol buffer sources.

    ```python
    proto_library(
        name = "foo",
        srcs = ["foo.proto"],
    )

    swift_proto_library(
        name = "foo_swift",
        protos = [":foo"],
    )
    ```

    You should have one proto_library and one swift_proto_library per proto package.
    If your protos depend on protos from other packages, add a dependency between
    the swift_proto_library targets which mirrors the dependency between the proto targets.

    ```python
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
