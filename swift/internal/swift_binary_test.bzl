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

"""Implementation of the `swift_binary` and `swift_test` rules."""

load(":api.bzl", "swift_common")
load(":derived_files.bzl", "derived_files")
load(":features.bzl", "is_feature_enabled")
load(":linking.bzl", "register_link_action")
load(":providers.bzl", "SwiftBinaryInfo", "SwiftToolchainInfo")
load(":utils.bzl", "expand_locations", "get_optionally")
load("@bazel_skylib//:lib.bzl", "dicts", "partial")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "CPP_LINK_EXECUTABLE_ACTION_NAME")

def _swift_linking_rule_impl(ctx, is_test):
    """The shared implementation function for `swift_{binary,test}`.

    Args:
        ctx: The rule context.
        is_test: A `Boolean` value indicating whether the binary is a test target.

    Returns:
        A list of providers to be propagated by the target being built.
    """

    # Bazel fails the build if you try to query a fragment that hasn't been declared, even
    # dynamically with `hasattr`/`getattr`. Thus, we have to use other information to determine
    # whether we can access the `objc` configuration.
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    objc_fragment = (ctx.fragments.objc if toolchain.supports_objc_interop else None)

    feature_configuration = swift_common.configure_features(
        toolchain = toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    linkopts = expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)

    additional_inputs = ctx.files.swiftc_inputs
    srcs = ctx.files.srcs

    out_bin = derived_files.executable(ctx.actions, target_name = ctx.label.name)
    objects_to_link = []
    additional_output_groups = {}
    compilation_providers = []

    link_args = ctx.actions.args()
    link_args.add("-o", out_bin)

    if not srcs:
        additional_inputs_to_linker = depset(direct = additional_inputs)
    else:
        module_name = ctx.attr.module_name
        if not module_name:
            module_name = swift_common.derive_module_name(ctx.label)

        compile_results = swift_common.compile_as_objects(
            actions = ctx.actions,
            arguments = [],
            compilation_mode = ctx.var["COMPILATION_MODE"],
            copts = copts,
            defines = ctx.attr.defines,
            feature_configuration = feature_configuration,
            module_name = module_name,
            srcs = srcs,
            swift_fragment = ctx.fragments.swift,
            target_name = ctx.label.name,
            toolchain = toolchain,
            additional_input_depsets = [depset(direct = additional_inputs)],
            configuration = ctx.configuration,
            deps = ctx.attr.deps,
            objc_fragment = objc_fragment,
        )
        link_args.add_all(compile_results.linker_flags)
        objects_to_link.extend(compile_results.output_objects)
        additional_inputs_to_linker = compile_results.compile_inputs + compile_results.linker_inputs

        dicts.add(additional_output_groups, compile_results.output_groups)
        compilation_providers.append(
            SwiftBinaryInfo(compile_options = compile_results.compile_options),
        )

    # TODO(b/70228246): Also support mostly-static and fully-dynamic modes, here and for the C++
    # toolchain args below.
    link_args.add_all(partial.call(
        toolchain.linker_opts_producer,
        is_static = True,
        is_test = is_test,
    ))

    # Enable LLVM coverage in CROSSTOOL if this is a coverage build. Note that we explicitly enable
    # LLVM format and disable GCC format because the former is the only one that Swift supports.
    if ctx.configuration.coverage_enabled:
        coverage_features_to_enable = ["llvm_coverage_map_format"]
        coverage_features_to_disable = ["gcc_coverage_map_format"]
    else:
        coverage_features_to_enable = []
        coverage_features_to_disable = []

    # Get additional linker flags from the C++ toolchain.
    cpp_toolchain = find_cpp_toolchain(ctx)
    cc_feature_configuration = cc_common.configure_features(
        cc_toolchain = cpp_toolchain,
        requested_features = (
            swift_common.get_enabled_features(feature_configuration) +
            ["static_linking_mode"] +
            coverage_features_to_enable
        ),
        unsupported_features = (
            swift_common.get_disabled_features(feature_configuration) +
            coverage_features_to_disable
        ),
    )
    variables = cc_common.create_link_variables(
        feature_configuration = cc_feature_configuration,
        cc_toolchain = cpp_toolchain,
        is_static_linking_mode = True,
    )
    link_cpp_toolchain_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = cc_feature_configuration,
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
        variables = variables,
    )
    link_args.add_all(link_cpp_toolchain_flags)

    register_link_action(
        actions = ctx.actions,
        action_environment = toolchain.action_environment,
        clang_executable = toolchain.clang_executable,
        deps = ctx.attr.deps + toolchain.implicit_deps,
        expanded_linkopts = linkopts,
        inputs = additional_inputs_to_linker,
        mnemonic = "SwiftLinkExecutable",
        objects = objects_to_link,
        outputs = [out_bin],
        rule_specific_args = link_args,
        toolchain = toolchain,
    )

    return [
        DefaultInfo(
            executable = out_bin,
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
        OutputGroupInfo(**additional_output_groups),
    ] + compilation_providers

def _swift_binary_impl(ctx):
    return _swift_linking_rule_impl(ctx, is_test = False)

def _swift_test_impl(ctx):
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    providers = _swift_linking_rule_impl(ctx, is_test = True)

    # TODO(b/79527231): Replace `instrumented_files` with a declared provider when it is available.
    return struct(
        instrumented_files = struct(
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        providers = providers + [
            testing.ExecutionInfo(toolchain.execution_requirements),
        ],
    )

swift_binary = rule(
    attrs = dicts.add(
        swift_common.compilation_attrs(),
        {
            "linkopts": attr.string_list(
                doc = """
Additional linker options that should be passed to `clang`. These strings are subject to
`$(location ...)` expansion.
""",
                mandatory = False,
            ),
            # Do not add references; temporary attribute for C++ toolchain Skylark migration.
            "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
        },
    ),
    doc = "Compiles and links Swift code into an executable binary.",
    executable = True,
    fragments = [
        "cpp",
        "objc",
        "swift",
    ],
    implementation = _swift_binary_impl,
)

swift_test = rule(
    attrs = dicts.add(
        swift_common.compilation_attrs(),
        {
            "linkopts": attr.string_list(
                doc = """
Additional linker options that should be passed to `clang`. These strings are subject to
`$(location ...)` expansion.
""",
                mandatory = False,
            ),
            # Do not add references; temporary attribute for C++ toolchain
            # Skylark migration.
            "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
        },
    ),
    doc = "Compiles and links Swift code into an executable test target.",
    executable = True,
    fragments = [
        "cpp",
        "objc",
        "swift",
    ],
    test = True,
    implementation = _swift_test_impl,
)
