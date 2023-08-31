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

"""Implementation of the `swift_binary` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "@build_bazel_rules_swift//swift/internal:compiling.bzl",
    "compile",
)
load(
    "@build_bazel_rules_swift//swift/internal:linking.bzl",
    "binary_rule_attrs",
    "configure_features_for_binary",
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
    "get_swift_toolchain",
    "use_swift_toolchain",
)
load(
    "@build_bazel_rules_swift//swift/internal:transitions.bzl",
    "cxx_interop_transition",
)
load(
    "@build_bazel_rules_swift//swift/internal:utils.bzl",
    "expand_locations",
    "get_compilation_contexts",
    "get_providers",
)
load(":module_name.bzl", "derive_swift_module_name")
load(":providers.bzl", "SwiftInfo")

visibility("public")

def _swift_binary_impl(ctx):
    swift_toolchain = get_swift_toolchain(ctx)

    feature_configuration = configure_features_for_binary(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    srcs = ctx.files.srcs
    output_groups = {}
    module_contexts = []

    # If the binary has sources, compile those first and collect the outputs to
    # be passed to the linker.
    if srcs:
        module_name = ctx.attr.module_name
        if not module_name:
            module_name = derive_swift_module_name(ctx.label)

        compile_result = compile(
            actions = ctx.actions,
            additional_inputs = ctx.files.swiftc_inputs,
            compilation_contexts = get_compilation_contexts(ctx.attr.deps),
            copts = expand_locations(
                ctx,
                ctx.attr.copts,
                ctx.attr.swiftc_inputs,
            ),
            defines = ctx.attr.defines,
            feature_configuration = feature_configuration,
            module_name = module_name,
            plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
            srcs = srcs,
            swift_infos = get_providers(ctx.attr.deps, SwiftInfo),
            swift_toolchain = swift_toolchain,
            target_name = ctx.label.name,
        )
        module_contexts.append(compile_result.module_context)
        compilation_outputs = compile_result.compilation_outputs
        supplemental_outputs = compile_result.supplemental_outputs
        output_groups = supplemental_compilation_output_groups(
            supplemental_outputs,
        )
    else:
        compilation_outputs = cc_common.create_compilation_outputs()

    # Apply the optional debugging outputs extension if the toolchain defines
    # one.
    debug_outputs_provider = swift_toolchain.debug_outputs_provider
    if debug_outputs_provider:
        debug_extension = debug_outputs_provider(ctx = ctx)
        additional_debug_outputs = debug_extension.additional_outputs
        variables_extension = debug_extension.variables_extension
    else:
        additional_debug_outputs = []
        variables_extension = {}

    linking_outputs = register_link_binary_action(
        actions = ctx.actions,
        additional_inputs = ctx.files.swiftc_inputs,
        additional_linking_contexts = [malloc_linking_context(ctx)],
        additional_outputs = additional_debug_outputs,
        feature_configuration = feature_configuration,
        compilation_outputs = compilation_outputs,
        deps = ctx.attr.deps,
        label = ctx.label,
        module_contexts = module_contexts,
        output_type = "executable",
        stamp = ctx.attr.stamp,
        swift_toolchain = swift_toolchain,
        user_link_flags = expand_locations(
            ctx,
            ctx.attr.linkopts,
            ctx.attr.swiftc_inputs,
        ) + ctx.fragments.cpp.linkopts,
        variables_extension = variables_extension,
    )

    return [
        DefaultInfo(
            executable = linking_outputs.executable,
            files = depset(
                [linking_outputs.executable] + additional_debug_outputs,
            ),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        OutputGroupInfo(**output_groups),
    ]

swift_binary = rule(
    attrs = dicts.add(
        binary_rule_attrs(stamp_default = -1),
        {
            "_allowlist_function_transition": attr.label(
                default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
            ),
        },
    ),
    doc = """\
Compiles and links Swift code into an executable binary.

On Linux, this rule produces an executable binary for the desired target
architecture.

On Apple platforms, this rule produces a _single-architecture_ binary; it does
not produce fat binaries. As such, this rule is mainly useful for creating Swift
tools intended to run on the local build machine.

If you want to create a multi-architecture binary or a bundled application,
please use one of the platform-specific application rules in
[rules_apple](https://github.com/bazelbuild/rules_apple) instead of
`swift_binary`.
""",
    cfg = cxx_interop_transition,
    executable = True,
    fragments = ["cpp"],
    implementation = _swift_binary_impl,
    toolchains = use_swift_toolchain(),
)
