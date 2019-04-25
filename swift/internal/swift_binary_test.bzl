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

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "CPP_LINK_EXECUTABLE_ACTION_NAME")
load(":api.bzl", "swift_common")
load(":derived_files.bzl", "derived_files")
load(":features.bzl", "SWIFT_FEATURE_BUNDLED_XCTESTS")
load(":linking.bzl", "register_link_action")
load(":providers.bzl", "SwiftToolchainInfo")
load(":swift_c_module_aspect.bzl", "swift_c_module_aspect")
load(":utils.bzl", "expand_locations")

# Attributes common to both `swift_binary` and `swift_test`.
_BINARY_RULE_ATTRS = dicts.add(
    swift_common.compilation_attrs(additional_deps_aspects = [swift_c_module_aspect]),
    {
        "linkopts": attr.string_list(
            doc = """
Additional linker options that should be passed to `clang`. These strings are subject to
`$(location ...)` expansion.
""",
            mandatory = False,
        ),
        "malloc": attr.label(
            default = Label("@bazel_tools//tools/cpp:malloc"),
            doc = """
Override the default dependency on `malloc`.

By default, Swift binaries are linked against `@bazel_tools//tools/cpp:malloc"`, which is an empty
library and the resulting binary will use libc's `malloc`. This label must refer to a `cc_library`
rule.
""",
            mandatory = False,
            providers = [[CcInfo]],
        ),
        # Do not add references; temporary attribute for C++ toolchain Skylark migration.
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
)

def _configure_features_for_binary(ctx, requested_features = [], unsupported_features = []):
    """Creates and returns the feature configuration for binary linking.

    This helper automatically handles common features for all Swift binary-creating targets, like
    code coverage.

    Args:
        ctx: The rule context.
        requested_features: Additional features that are requested for a particular rule/target.
        unsupported_features: Additional features that are unsupported for a particular
            rule/target.

    Returns:
        The `FeatureConfiguration` that was created.
    """
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]

    # Combine the features from the rule context with those passed into this function.
    requested_features = ctx.features + requested_features
    unsupported_features = ctx.disabled_features + unsupported_features

    # Enable LLVM coverage in CROSSTOOL if this is a coverage build. Note that we explicitly enable
    # LLVM format and disable GCC format because the former is the only one that Swift supports.
    if ctx.configuration.coverage_enabled:
        requested_features.append("llvm_coverage_map_format")
        unsupported_features.append("gcc_coverage_map_format")

    return swift_common.configure_features(
        requested_features = requested_features,
        swift_toolchain = toolchain,
        unsupported_features = unsupported_features,
    )

def _swift_linking_rule_impl(
        ctx,
        feature_configuration,
        is_test,
        toolchain,
        linkopts = []):
    """The shared implementation function for `swift_{binary,test}`.

    Args:
        ctx: The rule context.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        is_test: A `Boolean` value indicating whether the binary is a test target.
        toolchain: The `SwiftToolchainInfo` provider of the toolchain being used to build the
            target.
        linkopts: Additional rule-specific flags that should be passed to the linker.

    Returns:
        A tuple with two values: the `File` representing the binary that was linked, and a list of
        providers to be propagated by the target being built.
    """
    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    linkopts = list(linkopts) + expand_locations(ctx, ctx.attr.linkopts, ctx.attr.swiftc_inputs)
    linkopts += ctx.fragments.cpp.linkopts

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
            bin_dir = ctx.bin_dir,
            copts = copts,
            defines = ctx.attr.defines,
            feature_configuration = feature_configuration,
            module_name = module_name,
            srcs = srcs,
            target_name = ctx.label.name,
            toolchain = toolchain,
            additional_input_depsets = [depset(direct = additional_inputs)],
            deps = ctx.attr.deps,
            genfiles_dir = ctx.genfiles_dir,
        )
        link_args.add_all(compile_results.linker_flags)
        objects_to_link.extend(compile_results.output_objects)
        additional_inputs_to_linker = depset(
            direct = compile_results.linker_inputs,
            transitive = [compile_results.compile_inputs],
        )

        additional_output_groups = dicts.add(
            additional_output_groups,
            compile_results.output_groups,
        )

    # TODO(b/70228246): Also support mostly-static and fully-dynamic modes, here and for the C++
    # toolchain args below.
    link_args.add_all(partial.call(
        toolchain.linker_opts_producer,
        is_static = True,
        is_test = is_test,
    ))

    # Get additional linker flags from the C++ toolchain.
    cc_feature_configuration = swift_common.cc_feature_configuration(
        feature_configuration = feature_configuration,
    )
    variables = cc_common.create_link_variables(
        cc_toolchain = toolchain.cc_toolchain_info,
        feature_configuration = cc_feature_configuration,
        is_static_linking_mode = True,
    )
    link_cpp_toolchain_flags = cc_common.get_memory_inefficient_command_line(
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
        feature_configuration = cc_feature_configuration,
        variables = variables,
    )
    link_args.add_all(link_cpp_toolchain_flags)

    deps_to_link = ctx.attr.deps + toolchain.implicit_deps
    if ctx.attr.malloc:
        deps_to_link.append(ctx.attr.malloc)

    register_link_action(
        actions = ctx.actions,
        action_environment = toolchain.action_environment,
        clang_executable = toolchain.clang_executable,
        deps = deps_to_link,
        expanded_linkopts = linkopts,
        inputs = additional_inputs_to_linker,
        mnemonic = "SwiftLinkExecutable",
        objects = objects_to_link,
        outputs = [out_bin],
        progress_message = "Linking {}".format(out_bin.short_path),
        rule_specific_args = link_args,
        toolchain = toolchain,
    )

    return out_bin, compilation_providers + [
        OutputGroupInfo(**additional_output_groups),
    ]

def _create_xctest_runner(name, actions, binary, xctest_runner_template):
    """Creates a shell script that will bundle a test binary and launch the `xctest` helper tool.

    Args:
        name: The name of the target being built, which will be used as the basename of the bundle
            (followed by the `.xctest` bundle extension).
        actions: The context's actions object.
        binary: The `File` representing the test binary that should be bundled and executed.
        xctest_runner_template: The `File` that will be used as a template to generate the test
            runner shell script.

    Returns:
        A `File` representing the shell script that will launch the test bundle with the `xctest`
        tool.
    """
    xctest_runner = derived_files.xctest_runner_script(actions, name)

    actions.expand_template(
        is_executable = True,
        output = xctest_runner,
        template = xctest_runner_template,
        substitutions = {
            "%binary%": binary.short_path,
        },
    )

    return xctest_runner

def _swift_binary_impl(ctx):
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = _configure_features_for_binary(
        ctx = ctx,
        requested_features = ["static_linking_mode"],
    )

    binary, providers = _swift_linking_rule_impl(
        ctx,
        feature_configuration = feature_configuration,
        is_test = False,
        toolchain = toolchain,
    )

    return providers + [
        DefaultInfo(
            executable = binary,
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
    ]

def _swift_test_impl(ctx):
    toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = _configure_features_for_binary(
        ctx = ctx,
        requested_features = ["static_linking_mode"],
    )

    is_bundled = (toolchain.supports_objc_interop and
                  swift_common.is_enabled(
                      feature_configuration = feature_configuration,
                      feature_name = SWIFT_FEATURE_BUNDLED_XCTESTS,
                  ))

    # If we need to run the test in an .xctest bundle, the binary must have Mach-O type `MH_BUNDLE`
    # instead of `MH_EXECUTE`.
    # TODO(allevato): This should really be done in the toolchain's linker_opts_producer partial,
    # but it doesn't take the feature_configuration as an argument. We should update it to do so.
    linkopts = ["-Wl,-bundle"] if is_bundled else []

    binary, providers = _swift_linking_rule_impl(
        ctx,
        feature_configuration = feature_configuration,
        is_test = True,
        linkopts = linkopts,
        toolchain = toolchain,
    )

    # If the tests are to be bundled, create the test runner script as the rule's executable and
    # place the binary in runfiles so that it can be copied into place. Otherwise, just use the
    # binary itself as the executable to launch.
    # TODO(b/65413470): Make the output of the rule _itself_ an `.xctest` bundle once some
    # limitations of directory artifacts are resolved.
    if is_bundled:
        xctest_runner = _create_xctest_runner(
            name = ctx.label.name,
            actions = ctx.actions,
            binary = binary,
            xctest_runner_template = ctx.file._xctest_runner_template,
        )
        additional_test_outputs = [binary]
        executable = xctest_runner
    else:
        additional_test_outputs = []
        executable = binary

    test_environment = dicts.add(
        toolchain.action_environment,
        {"TEST_BINARIES_FOR_LLVM_COV": binary.short_path},
    )

    return providers + [
        DefaultInfo(
            executable = executable,
            files = depset(direct = [executable] + additional_test_outputs),
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data + additional_test_outputs,
                transitive_files = ctx.attr._apple_coverage_support.files,
            ),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        testing.ExecutionInfo(toolchain.execution_requirements),
        testing.TestEnvironment(test_environment),
    ]

swift_binary = rule(
    attrs = _BINARY_RULE_ATTRS,
    doc = """
Compiles and links Swift code into an executable binary.

On Linux, this rule produces an executable binary for the desired target architecture.

On Apple platforms, this rule produces a _single-architecture_ binary; it does not produce fat
binaries. As such, this rule is mainly useful for creating Swift tools intended to run on the
local build machine. However, for historical reasons, the default Apple platform in Bazel is
**iOS** instead of macOS. Therefore, if you wish to build a simple single-architecture Swift
binary that can run on macOS, you must specify the correct CPU and platform on the command line as
follows:

```shell
$ bazel build //package:target
```

If you want to create a multi-architecture binary or a bundled application, please use one of the
platform-specific application rules in [rules_apple](https://github.com/bazelbuild/rules_apple)
instead of `swift_binary`.
""",
    executable = True,
    fragments = ["cpp"],
    implementation = _swift_binary_impl,
)

swift_test = rule(
    attrs = dicts.add(
        _BINARY_RULE_ATTRS,
        {
            "_apple_coverage_support": attr.label(
                cfg = "host",
                default = Label("@build_bazel_apple_support//tools:coverage_support"),
            ),
            "_xctest_runner_template": attr.label(
                allow_single_file = True,
                default = Label(
                    "@build_bazel_rules_swift//tools/xctest_runner:xctest_runner_template",
                ),
            ),
        },
    ),
    doc = """
Compiles and links Swift code into an executable test target.

The behavior of `swift_test` differs slightly for macOS targets, in order to provide seamless
integration with Apple's XCTest framework. The output of the rule is still a binary, but one whose
Mach-O type is `MH_BUNDLE` (a loadable bundle). Thus, the binary cannot be launched directly.
Instead, running `bazel test` on the target will launch a test runner script that copies it into an
`.xctest` bundle directory and then launches the `xctest` helper tool from Xcode, which uses
Objective-C runtime reflection to locate the tests.

On Linux, the output of a `swift_test` is a standard executable binary, because the implementation
of XCTest on that platform currently requires authors to explicitly list the tests that are present
and run them from their main program.

Test bundling on macOS can be disabled on a per-target basis, if desired. You may wish to do this if
you are not using XCTest, but rather a different test framework (or no framework at all) where the
pass/fail outcome is represented as a zero/non-zero exit code (as is the case with other Bazel test
rules like `cc_test`). To do so, disable the `"swift.bundled_xctests"` feature on the target:

```python
swift_test(
    name = "MyTests",
    srcs = [...],
    features = ["-swift.bundled_xctests"],
)
```

You can also disable this feature for all the tests in a package by applying it to your BUILD file's
`package()` declaration instead of the individual targets.
""",
    executable = True,
    fragments = ["cpp"],
    test = True,
    implementation = _swift_test_impl,
)
