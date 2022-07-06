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
load(":compiling.bzl", "output_groups_from_other_compilation_outputs")
load(":derived_files.bzl", "derived_files")
load(":feature_names.bzl", "SWIFT_FEATURE_BUNDLED_XCTESTS")
load(":linking.bzl", "register_link_binary_action")
load(":providers.bzl", "SwiftToolchainInfo")
load(":swift_clang_module_aspect.bzl", "swift_clang_module_aspect")
load(":swift_common.bzl", "swift_common")
load(":utils.bzl", "expand_locations")

def _binary_rule_attrs(stamp_default):
    """Returns attributes common to both `swift_binary` and `swift_test`.

    Args:
        stamp_default: The default value of the `stamp` attribute.

    Returns:
        A `dict` of attributes for a binary or test rule.
    """
    return dicts.add(
        swift_common.compilation_attrs(
            additional_deps_aspects = [swift_clang_module_aspect],
            requires_srcs = False,
        ),
        {
            "linkopts": attr.string_list(
                doc = """\
Additional linker options that should be passed to `clang`. These strings are
subject to `$(location ...)` expansion.
""",
                mandatory = False,
            ),
            "malloc": attr.label(
                default = Label("@bazel_tools//tools/cpp:malloc"),
                doc = """\
Override the default dependency on `malloc`.

By default, Swift binaries are linked against `@bazel_tools//tools/cpp:malloc"`,
which is an empty library and the resulting binary will use libc's `malloc`.
This label must refer to a `cc_library` rule.
""",
                mandatory = False,
                providers = [[CcInfo]],
            ),
            "stamp": attr.int(
                default = stamp_default,
                doc = """\
Enable or disable link stamping; that is, whether to encode build information
into the binary. Possible values are:

* `stamp = 1`: Stamp the build information into the binary. Stamped binaries are
  only rebuilt when their dependencies change. Use this if there are tests that
  depend on the build information.

* `stamp = 0`: Always replace build information by constant values. This gives
  good build result caching.

* `stamp = -1`: Embedding of build information is controlled by the
  `--[no]stamp` flag.
""",
                mandatory = False,
            ),
            # Do not add references; temporary attribute for C++ toolchain
            # Starlark migration.
            "_cc_toolchain": attr.label(
                default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            ),
            # A late-bound attribute denoting the value of the `--custom_malloc`
            # command line flag (or None if the flag is not provided).
            "_custom_malloc": attr.label(
                default = configuration_field(
                    fragment = "cpp",
                    name = "custom_malloc",
                ),
                providers = [[CcInfo]],
            ),
            # TODO(b/119082664): Used internally only.
            "_grep_includes": attr.label(
                allow_single_file = True,
                cfg = "exec",
                default = Label("@bazel_tools//tools/cpp:grep-includes"),
                executable = True,
            ),
        },
    )

def _configure_features_for_binary(
        ctx,
        requested_features = [],
        unsupported_features = []):
    """Creates and returns the feature configuration for binary linking.

    This helper automatically handles common features for all Swift
    binary-creating targets, like code coverage.

    Args:
        ctx: The rule context.
        requested_features: Additional features that are requested for a
            particular rule/target.
        unsupported_features: Additional features that are unsupported for a
            particular rule/target.

    Returns:
        The `FeatureConfiguration` that was created.
    """
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]

    # Combine the features from the rule context with those passed into this
    # function.
    requested_features = ctx.features + requested_features
    unsupported_features = ctx.disabled_features + unsupported_features

    # Enable LLVM coverage in CROSSTOOL if this is a coverage build. Note that
    # we explicitly enable LLVM format and disable GCC format because the former
    # is the only one that Swift supports.
    if ctx.configuration.coverage_enabled:
        requested_features.append("llvm_coverage_map_format")
        unsupported_features.append("gcc_coverage_map_format")

    return swift_common.configure_features(
        ctx = ctx,
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = unsupported_features,
    )

def _swift_linking_rule_impl(
        ctx,
        binary_path,
        feature_configuration,
        swift_toolchain,
        linkopts = []):
    """The shared implementation function for `swift_{binary,test}`.

    Args:
        ctx: The rule context.
        binary_path: The path to output the linked binary to.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain
            being used to build the target.
        linkopts: Additional rule-specific flags that should be passed to the
            linker.

    Returns:
        A tuple with three elements: the `CcCompilationOutputs` containing the
        object files that were compiled for the sources in the binary/test
        target (if any), the `LinkingOutputs` containing the executable
        binary that was linked, and a list of providers to be propagated by the
        target being built.
    """
    additional_inputs = ctx.files.swiftc_inputs
    additional_inputs_to_linker = list(additional_inputs)
    additional_linking_contexts = []
    cc_feature_configuration = swift_common.cc_feature_configuration(
        feature_configuration = feature_configuration,
    )
    srcs = ctx.files.srcs
    user_link_flags = list(linkopts)

    # If the rule has sources, compile those first and collect the outputs to
    # be passed to the linker.
    if srcs:
        module_name = ctx.attr.module_name
        if not module_name:
            module_name = swift_common.derive_module_name(ctx.label)

        copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)

        module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
            actions = ctx.actions,
            additional_inputs = additional_inputs,
            copts = copts,
            defines = ctx.attr.defines,
            deps = ctx.attr.deps,
            feature_configuration = feature_configuration,
            module_name = module_name,
            srcs = srcs,
            swift_toolchain = swift_toolchain,
            target_name = ctx.label.name,
            workspace_name = ctx.workspace_name,
        )
        output_groups = output_groups_from_other_compilation_outputs(
            other_compilation_outputs = other_compilation_outputs,
        )

        linking_context, _ = swift_common.create_linking_context_from_compilation_outputs(
            actions = ctx.actions,
            alwayslink = True,
            compilation_outputs = cc_compilation_outputs,
            feature_configuration = feature_configuration,
            label = ctx.label,
            linking_contexts = [
                dep[CcInfo].linking_context
                for dep in ctx.attr.deps
                if CcInfo in dep
            ],
            module_context = module_context,
            swift_toolchain = swift_toolchain,
        )
        additional_linking_contexts.append(linking_context)
    else:
        module_context = None
        cc_compilation_outputs = cc_common.create_compilation_outputs()
        output_groups = {}

    # Collect linking contexts from any of the toolchain's implicit
    # dependencies.
    for cc_info in swift_toolchain.implicit_deps_providers.cc_infos:
        additional_linking_contexts.append(cc_info.linking_context)

    # If a custom malloc implementation has been provided, pass that to the
    # linker as well.
    malloc = ctx.attr._custom_malloc or ctx.attr.malloc
    additional_linking_contexts.append(malloc[CcInfo].linking_context)

    # Finally, consider linker flags in the `linkopts` attribute and the
    # `--linkopt` command line flag last, so they get highest priority.
    user_link_flags.extend(expand_locations(
        ctx,
        ctx.attr.linkopts,
        ctx.attr.swiftc_inputs,
    ))
    user_link_flags.extend(ctx.fragments.cpp.linkopts)

    linking_outputs = register_link_binary_action(
        actions = ctx.actions,
        additional_inputs = additional_inputs_to_linker,
        additional_linking_contexts = additional_linking_contexts,
        cc_feature_configuration = cc_feature_configuration,
        # This is already collected from `linking_context`.
        compilation_outputs = None,
        deps = ctx.attr.deps,
        grep_includes = ctx.file._grep_includes,
        name = binary_path,
        output_type = "executable",
        owner = ctx.label,
        stamp = ctx.attr.stamp,
        swift_toolchain = swift_toolchain,
        user_link_flags = user_link_flags,
    )

    providers = [OutputGroupInfo(**output_groups)]

    return cc_compilation_outputs, linking_outputs, providers

def _create_xctest_runner(name, actions, executable, xctest_runner_template):
    """Creates a script that will launch `xctest` with the given test bundle.

    Args:
        name: The name of the target being built, which will be used as the
            basename of the test runner script.
        actions: The context's actions object.
        executable: The `File` representing the executable inside the `.xctest`
            bundle that should be executed.
        xctest_runner_template: The `File` that will be used as a template to
            generate the test runner shell script.

    Returns:
        A `File` representing the shell script that will launch the test bundle
        with the `xctest` tool.
    """
    xctest_runner = derived_files.xctest_runner_script(
        actions = actions,
        target_name = name,
    )

    actions.expand_template(
        is_executable = True,
        output = xctest_runner,
        template = xctest_runner_template,
        substitutions = {
            "%executable%": executable.short_path,
        },
    )

    return xctest_runner

def _swift_binary_impl(ctx):
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = _configure_features_for_binary(
        ctx = ctx,
        requested_features = ["static_linking_mode"],
    )

    _, linking_outputs, providers = _swift_linking_rule_impl(
        ctx,
        binary_path = ctx.label.name,
        feature_configuration = feature_configuration,
        swift_toolchain = swift_toolchain,
    )

    return providers + [
        DefaultInfo(
            executable = linking_outputs.executable,
            runfiles = ctx.runfiles(
                collect_data = True,
                collect_default = True,
                files = ctx.files.data,
            ),
        ),
    ]

def _swift_test_impl(ctx):
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]
    feature_configuration = _configure_features_for_binary(
        ctx = ctx,
        requested_features = ["static_linking_mode"],
    )

    is_bundled = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_BUNDLED_XCTESTS,
    )

    # If we need to run the test in an .xctest bundle, the binary must have
    # Mach-O type `MH_BUNDLE` instead of `MH_EXECUTE`.
    linkopts = ["-Wl,-bundle"] if is_bundled else []
    xctest_bundle_binary = "{0}.xctest/Contents/MacOS/{0}".format(ctx.label.name)
    binary_path = xctest_bundle_binary if is_bundled else ctx.label.name

    _, linking_outputs, providers = _swift_linking_rule_impl(
        ctx,
        binary_path = binary_path,
        feature_configuration = feature_configuration,
        linkopts = linkopts,
        swift_toolchain = swift_toolchain,
    )

    # If the tests are to be bundled, create the bundle and the test runner
    # script that launches it via `xctest`. Otherwise, just use the binary
    # itself as the executable to launch.
    if is_bundled:
        xctest_runner = _create_xctest_runner(
            name = ctx.label.name,
            actions = ctx.actions,
            executable = linking_outputs.executable,
            xctest_runner_template = ctx.file._xctest_runner_template,
        )
        additional_test_outputs = [linking_outputs.executable]
        executable = xctest_runner
    else:
        additional_test_outputs = []
        executable = linking_outputs.executable

    test_environment = dicts.add(
        swift_toolchain.test_configuration.env,
        {"TEST_BINARIES_FOR_LLVM_COV": linking_outputs.executable.short_path},
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
        testing.ExecutionInfo(
            swift_toolchain.test_configuration.execution_requirements,
        ),
        testing.TestEnvironment(test_environment),
    ]

swift_binary = rule(
    attrs = _binary_rule_attrs(stamp_default = -1),
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
    executable = True,
    fragments = ["cpp"],
    implementation = _swift_binary_impl,
)

swift_test = rule(
    attrs = dicts.add(
        _binary_rule_attrs(stamp_default = 0),
        {
            "_apple_coverage_support": attr.label(
                cfg = "exec",
                default = Label(
                    "@build_bazel_apple_support//tools:coverage_support",
                ),
            ),
            "_xctest_runner_template": attr.label(
                allow_single_file = True,
                default = Label(
                    "@build_bazel_rules_swift//tools/xctest_runner:xctest_runner_template",
                ),
            ),
        },
    ),
    doc = """\
Compiles and links Swift code into an executable test target.

The behavior of `swift_test` differs slightly for macOS targets, in order to
provide seamless integration with Apple's XCTest framework. The output of the
rule is still a binary, but one whose Mach-O type is `MH_BUNDLE` (a loadable
bundle). Thus, the binary cannot be launched directly. Instead, running
`bazel test` on the target will launch a test runner script that copies it into
an `.xctest` bundle directory and then launches the `xctest` helper tool from
Xcode, which uses Objective-C runtime reflection to locate the tests.

On Linux, the output of a `swift_test` is a standard executable binary, because
the implementation of XCTest on that platform currently requires authors to
explicitly list the tests that are present and run them from their main program.

Test bundling on macOS can be disabled on a per-target basis, if desired. You
may wish to do this if you are not using XCTest, but rather a different test
framework (or no framework at all) where the pass/fail outcome is represented as
a zero/non-zero exit code (as is the case with other Bazel test rules like
`cc_test`). To do so, disable the `"swift.bundled_xctests"` feature on the
target:

```python
swift_test(
    name = "MyTests",
    srcs = [...],
    features = ["-swift.bundled_xctests"],
)
```

You can also disable this feature for all the tests in a package by applying it
to your BUILD file's `package()` declaration instead of the individual targets.
""",
    executable = True,
    fragments = ["cpp"],
    test = True,
    implementation = _swift_test_impl,
)
