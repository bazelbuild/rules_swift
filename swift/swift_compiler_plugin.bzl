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

"""Implementation of the `swift_compiler_plugin` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "@build_bazel_rules_swift//swift/internal:binary_attrs.bzl",
    "binary_rule_attrs",
)
load(
    "@build_bazel_rules_swift//swift/internal:compiling.bzl",
    "compile",
)
load(
    "@build_bazel_rules_swift//swift/internal:linking.bzl",
    "configure_features_for_binary",
    "create_linking_context_from_compilation_outputs",
    "entry_point_function_name",
    "malloc_linking_context",
    "register_link_binary_action",
)
load(
    "@build_bazel_rules_swift//swift/internal:output_groups.bzl",
    "supplemental_compilation_output_groups",
)
load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    "SwiftCompilerPluginInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl",
    "find_all_toolchains",
    "use_all_toolchains",
)
load(
    "@build_bazel_rules_swift//swift/internal:utils.bzl",
    "expand_locations",
    "get_compilation_contexts",
    "get_providers",
)
load(":module_name.bzl", "derive_swift_module_name")
load(":providers.bzl", "SwiftBinaryInfo", "SwiftInfo", "SwiftOverlayInfo")

visibility("public")

def _swift_compiler_plugin_impl(ctx):
    toolchains = find_all_toolchains(ctx)
    feature_configuration = configure_features_for_binary(
        ctx = ctx,
        requested_features = ctx.features,
        toolchains = toolchains,
        unsupported_features = ctx.disabled_features,
    )

    deps = ctx.attr.deps
    srcs = ctx.files.srcs
    module_contexts = []

    if not srcs:
        fail("A compiler plugin must have at least one file in 'srcs'.")

    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    c_copts = expand_locations(ctx, ctx.attr.c_copts, ctx.attr.swiftc_inputs)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = derive_swift_module_name(
            ctx.label,
            feature_configuration = feature_configuration,
        )
    entry_point_name = entry_point_function_name(module_name)

    compile_result = compile(
        actions = ctx.actions,
        additional_inputs = ctx.files.swiftc_inputs,
        compilation_contexts = get_compilation_contexts(ctx.attr.deps),
        copts = copts + [
            # Compiler plugins always define a `CompilerPlugin`-conforming type
            # that is attributed with `@main`.
            "-parse-as-library",
            # Use a custom entry point name so that the macro can also be linked
            # into another process (like a test executable) without having its
            # main function collide.
            "-Xfrontend",
            "-entry-point-function-name",
            "-Xfrontend",
            entry_point_name,
        ],
        c_copts = c_copts,
        defines = ctx.attr.defines,
        feature_configuration = feature_configuration,
        module_name = module_name,
        plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
        srcs = srcs,
        swift_infos = get_providers(deps, SwiftInfo),
        toolchains = toolchains,
        target_name = ctx.label.name,
    )
    module_context = compile_result.module_context
    module_contexts.append(module_context)
    compilation_outputs = compile_result.compilation_outputs
    supplemental_outputs = compile_result.supplemental_outputs

    # Apply the optional debugging outputs extension if the toolchain defines
    # one.
    debug_outputs_provider = toolchains.swift.debug_outputs_provider
    if debug_outputs_provider:
        debug_extension = debug_outputs_provider(ctx = ctx)
        additional_debug_outputs = debug_extension.additional_outputs
        variables_extension = debug_extension.variables_extension
    else:
        additional_debug_outputs = []
        variables_extension = {}

    binary_linking_outputs = register_link_binary_action(
        actions = ctx.actions,
        additional_inputs = ctx.files.swiftc_inputs,
        additional_linking_contexts = [malloc_linking_context(ctx)],
        additional_outputs = additional_debug_outputs,
        feature_configuration = feature_configuration,
        compilation_outputs = compilation_outputs,
        deps = deps,
        label = ctx.label,
        module_contexts = module_contexts,
        output_type = "executable",
        stamp = ctx.attr.stamp,
        toolchains = toolchains,
        user_link_flags = expand_locations(
            ctx,
            ctx.attr.linkopts,
            ctx.attr.swiftc_inputs,
        ) + ctx.fragments.cpp.linkopts + (
            # When linking the plugin binary, make sure we use the correct entry
            # point name.
            toolchains.swift.entry_point_linkopts_provider(
                entry_point_name = entry_point_name,
            ).linkopts
        ),
        variables_extension = variables_extension,
    )

    linking_context, _ = (
        create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            additional_inputs = ctx.files.swiftc_inputs,
            alwayslink = True,
            compilation_outputs = compilation_outputs,
            feature_configuration = feature_configuration,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in deps
                if CcInfo in dep
            ] + [
                dep[SwiftOverlayInfo].linking_context
                for dep in deps
                if SwiftOverlayInfo in dep
            ],
            module_context = module_context,
            toolchains = toolchains,
            user_link_flags = ctx.attr.linkopts,
        )
    )

    return [
        DefaultInfo(
            executable = binary_linking_outputs.executable,
            files = depset(
                [binary_linking_outputs.executable] + additional_debug_outputs,
            ),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        OutputGroupInfo(
            **supplemental_compilation_output_groups(supplemental_outputs)
        ),
        SwiftBinaryInfo(
            cc_info = CcInfo(
                compilation_context = module_context.clang.compilation_context,
                linking_context = linking_context,
            ),
            swift_info = compile_result.swift_info,
        ),
        SwiftCompilerPluginInfo(
            executable = binary_linking_outputs.executable,
            module_names = depset([module_name]),
        ),
    ]

swift_compiler_plugin = rule(
    attrs = dicts.add(
        binary_rule_attrs(
            exclude_env = True,
            # Do not stamp macro binaries by default to prevent frequent
            # rebuilds.
            stamp_default = 0,
        ),
        {
        },
    ),
    doc = """\
Compiles and links a Swift compiler plugin (for example, a macro).

A compiler plugin is a standalone executable that minimally implements the
`CompilerPlugin` protocol from the `SwiftCompilerPlugin` module in swift-syntax.
As of the time of this writing (Xcode 15.0), a compiler plugin can contain one
or more macros, which can be associated with other Swift targets to perform
syntax-tree-based expansions.

When a `swift_compiler_plugin` target is listed in the `plugins` attribute of a
`swift_library`, it will be loaded by that library and any targets that directly
depend on it. (The `plugins` attribute also exists on `swift_binary`,
`swift_test`, and `swift_compiler_plugin` itself, to support plugins that are
only used within those targets.)

Compiler plugins also support being built as a library so that they can be
tested. The `swift_test` rule can contain `swift_compiler_plugin` targets in its
`deps`, and the plugin's module can be imported by the test's sources so that
unit tests can be written against the plugin.
""",
    exec_groups = {
        # The `plugins` attribute associates its `exec` transition with this
        # execution group. Even though the group is otherwise not used in this
        # rule, we must resolve the Swift toolchain in this execution group so
        # that the execution platform of the plugins will have the same
        # constraints as the execution platform as the other uses of the same
        # toolchain, ensuring that they don't get built for mismatched
        # platforms.
        "swift_plugins": exec_group(
            toolchains = use_all_toolchains(),
        ),
    },
    executable = True,
    fragments = ["cpp"],
    implementation = _swift_compiler_plugin_impl,
    toolchains = use_all_toolchains(),
)
