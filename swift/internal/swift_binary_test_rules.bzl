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
load(":env_expansion.bzl", "expanded_env")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT",
    "SWIFT_FEATURE_BUNDLED_XCTESTS",
)
load(":linking.bzl", "binary_rule_attrs", "configure_features_for_binary", "register_link_binary_action")
load(":providers.bzl", "SwiftCompilerPluginInfo", "SwiftToolchainInfo")
load(":swift_common.bzl", "swift_common")
load(":utils.bzl", "expand_locations", "get_providers", "include_developer_search_paths")

def _maybe_parse_as_library_copts(srcs):
    """Returns a list of compiler flags depending on `main.swift`'s presence.

    Now that the `@main` attribute exists and is becoming more common, in the
    case there is a single file not named `main.swift`, we assume that it has a
    `@main` annotation, in which case it needs to be parsed as a library, not
    as if it has top level code. In the case this is the wrong assumption,
    compilation or linking will fail.

    Args:
        srcs: A list of source files to check for the presence of `main.swift`.

    Returns:
        A list of compiler flags to add to `copts`
    """
    use_parse_as_library = len(srcs) == 1 and \
                           srcs[0].basename != "main.swift"
    return ["-parse-as-library"] if use_parse_as_library else []

def _swift_linking_rule_impl(
        ctx,
        binary_path,
        feature_configuration,
        swift_toolchain,
        additional_linking_contexts = [],
        extra_link_deps = [],
        extra_swift_infos = [],
        linkopts = []):
    """The shared implementation function for `swift_{binary,test}`.

    Args:
        ctx: The rule context.
        binary_path: The path to output the linked binary to.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain
            being used to build the target.
        additional_linking_contexts: Additional linking contexts that provide
            libraries or flags that should be linked into the executable.
        extra_link_deps: Additional dependencies that should be linked into the
            binary.
        extra_swift_infos: Extra `SwiftInfo` providers that aren't contained
            by the `deps` of the target being compiled but are required for
            compilation.
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
    additional_linking_contexts = list(additional_linking_contexts)
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

        copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs) + \
                _maybe_parse_as_library_copts(srcs)

        include_dev_srch_paths = include_developer_search_paths(ctx.attr)

        module_context, cc_compilation_outputs, other_compilation_outputs = swift_common.compile(
            actions = ctx.actions,
            additional_inputs = additional_inputs,
            copts = copts,
            defines = ctx.attr.defines,
            deps = ctx.attr.deps,
            extra_swift_infos = extra_swift_infos,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            module_name = module_name,
            package_name = ctx.attr.package_name,
            plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
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
            include_dev_srch_paths = include_dev_srch_paths,
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
        deps = ctx.attr.deps + extra_link_deps,
        name = binary_path,
        output_type = "executable",
        owner = ctx.label,
        stamp = ctx.attr.stamp,
        swift_toolchain = swift_toolchain,
        user_link_flags = user_link_flags,
    )

    if module_context:
        modules = [
            swift_common.create_module(
                name = module_context.name,
                compilation_context = module_context.compilation_context,
                # The rest of the fields are intentionally ommited, as we only
                # want to expose the compilation_context
            ),
        ]
    else:
        modules = []

    providers = [
        OutputGroupInfo(**output_groups),
        swift_common.create_swift_info(
            modules = modules,
        ),
    ]

    return cc_compilation_outputs, linking_outputs, providers

def _create_xctest_runner(name, actions, add_target_name_to_output_path, executable, xctest_runner_template):
    """Creates a script that will launch `xctest` with the given test bundle.

    Args:
        name: The name of the target being built, which will be used as the
            basename of the test runner script.
        actions: The context's actions object.
        add_target_name_to_output_path: Add target_name in output path. More info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
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
        add_target_name_to_output_path = add_target_name_to_output_path,
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
    feature_configuration = configure_features_for_binary(
        ctx = ctx,
        requested_features = ["static_linking_mode"],
    )

    add_target_name_to_output_path = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT,
    )

    _, linking_outputs, providers = _swift_linking_rule_impl(
        ctx,
        binary_path = derived_files.path(ctx, add_target_name_to_output_path, ctx.label.name),
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
    feature_configuration = configure_features_for_binary(
        ctx = ctx,
        requested_features = ["static_linking_mode"],
    )

    is_bundled = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_BUNDLED_XCTESTS,
    )

    add_target_name_to_output_path = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT,
    )

    # If we need to run the test in an .xctest bundle, the binary must have
    # Mach-O type `MH_BUNDLE` instead of `MH_EXECUTE`.
    linkopts = ["-Wl,-bundle"] if is_bundled else []
    xctest_bundle_binary = "{0}.xctest/Contents/MacOS/{0}".format(ctx.label.name)
    binary_path = xctest_bundle_binary if is_bundled else ctx.label.name

    # `swift_common.is_enabled` isn't used, as it requires the prefix of the
    # feature to start with `swift.`
    swizzle_absolute_xcttestsourcelocation = (
        "apple.swizzle_absolute_xcttestsourcelocation" in
        feature_configuration._enabled_features
    )

    extra_link_deps = []
    if swizzle_absolute_xcttestsourcelocation:
        extra_link_deps.append(ctx.attr._swizzle_absolute_xcttestsourcelocation)

    # We also need to collect nested providers from `SwiftCompilerPluginInfo`
    # since we support testing those.
    extra_swift_infos = []
    additional_linking_contexts = []
    for dep in ctx.attr.deps:
        if SwiftCompilerPluginInfo in dep:
            plugin_info = dep[SwiftCompilerPluginInfo]
            extra_swift_infos.append(plugin_info.swift_info)
            additional_linking_contexts.append(plugin_info.cc_info.linking_context)

    _, linking_outputs, providers = _swift_linking_rule_impl(
        ctx,
        additional_linking_contexts = additional_linking_contexts,
        binary_path = binary_path,
        extra_swift_infos = extra_swift_infos,
        extra_link_deps = extra_link_deps,
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
            add_target_name_to_output_path = add_target_name_to_output_path,
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
        expanded_env.get_expanded_env(ctx, {}),
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
    attrs = binary_rule_attrs(
        additional_deps_providers = [[SwiftCompilerPluginInfo]],
        stamp_default = -1,
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
    executable = True,
    fragments = ["cpp"],
    implementation = _swift_binary_impl,
)

swift_test = rule(
    attrs = dicts.add(
        binary_rule_attrs(
            additional_deps_providers = [[SwiftCompilerPluginInfo]],
            stamp_default = 0,
        ),
        {
            "env": attr.string_dict(
                doc = """
                Dictionary of environment variables that should be set during the test execution.
                """,
            ),
            "_apple_coverage_support": attr.label(
                cfg = "exec",
                default = Label(
                    "@build_bazel_apple_support//tools:coverage_support",
                ),
            ),
            "_swizzle_absolute_xcttestsourcelocation": attr.label(
                default = Label(
                    "@build_bazel_rules_swift//swift/internal:swizzle_absolute_xcttestsourcelocation",
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

If integrating with Xcode, the relative paths in test binaries can prevent the
Issue navigator from working for test failures. To work around this, you can
have the paths made absolute via swizzling by enabling the
`"apple.swizzle_absolute_xcttestsourcelocation"` feature. You'll also need to
set the `BUILD_WORKSPACE_DIRECTORY` environment variable in your scheme to the
root of your workspace (i.e. `$(SRCROOT)`).

A subset of tests for a given target can be executed via the `--test_filter` parameter:

```
bazel test //:Tests --test_filter=TestModuleName.TestClassName/testMethodName
```
""",
    executable = True,
    fragments = ["cpp"],
    test = True,
    implementation = _swift_test_impl,
)
