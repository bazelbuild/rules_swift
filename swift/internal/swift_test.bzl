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
load(":derived_files.bzl", "derived_files")
load(":env_expansion.bzl", "expanded_env")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_BUNDLED_XCTESTS",
)
load(
    ":linking.bzl",
    "binary_rule_attrs",
    "configure_features_for_binary",
    "malloc_linking_context",
    "register_link_binary_action",
)
load(":output_groups.bzl", "supplemental_compilation_output_groups")
load(
    ":providers.bzl",
    "SwiftCompilerPluginInfo",
    "SwiftInfo",
    "SwiftSymbolGraphInfo",
    "SwiftToolchainInfo",
)
load(":swift_common.bzl", "swift_common")
load(":swift_symbol_graph_aspect.bzl", "test_discovery_symbol_graph_aspect")
load(
    ":utils.bzl",
    "expand_locations",
    "get_providers",
    "include_developer_search_paths",
)

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

def _create_xctest_bundle(name, actions, binary):
    """Creates an `.xctest` bundle that contains the given binary.

    Args:
        name: The name of the target being built, which will be used as the
            basename of the bundle (followed by the .xctest bundle extension).
        actions: The context's actions object.
        binary: The binary that will be copied into the test bundle.

    Returns:
        A `File` (tree artifact) representing the `.xctest` bundle.
    """
    xctest_bundle = derived_files.xctest_bundle(
        actions = actions,
        target_name = name,
    )

    args = actions.args()
    args.add(xctest_bundle.path)
    args.add(binary)

    # When XCTest loads this bundle, it will create an instance of this class
    # which will register the observer that writes the XML output.
    plist = '{ NSPrincipalClass = "BazelXMLTestObserverRegistration"; }'

    actions.run_shell(
        arguments = [args],
        command = (
            'mkdir -p "$1/Contents/MacOS" && ' +
            'cp "$2" "$1/Contents/MacOS" && ' +
            'echo \'{}\' > "$1/Contents/Info.plist"'.format(plist)
        ),
        inputs = [binary],
        mnemonic = "SwiftCreateTestBundle",
        outputs = [xctest_bundle],
        progress_message = "Creating test bundle for {}".format(name),
    )

    return xctest_bundle

def _create_xctest_runner(name, actions, bundle, xctest_runner_template):
    """Creates a script that will launch `xctest` with the given test bundle.

    Args:
        name: The name of the target being built, which will be used as the
            basename of the test runner script.
        actions: The context's actions object.
        bundle: The `File` representing the `.xctest` bundle that should be
            executed.
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
            "%bundle%": bundle.short_path,
        },
    )

    return xctest_runner

def _generate_test_discovery_srcs(*, actions, deps, name, test_discoverer):
    """Generate Swift sources to run discovered XCTest-style tests.

    Args:
        actions: The context's actions object.
        deps: The list of direct dependencies of the test target.
        name: The name of the target being built, which will be used to derive
            the basename of the directory containing the generated files.
        test_discoverer: The executable `File` representing the test discoverer
            tool that will be spawned to generate the test runner sources.

    Returns:
        A list of `File`s representing generated `.swift` source files that
        should be compiled as part of the test target.
    """
    inputs = []
    outputs = []
    args = actions.args()

    # For each direct dependency/module that we have a symbol graph for (i.e.,
    # every testonly dependency), declare a `.swift` source file where the
    # discovery tool will generate an extension that lists the test entries for
    # the classes/methods found in that module.
    for dep in deps:
        if SwiftSymbolGraphInfo not in dep:
            continue

        symbol_graph_info = dep[SwiftSymbolGraphInfo]

        for symbol_graph in symbol_graph_info.direct_symbol_graphs:
            output_file = actions.declare_file(
                "{target}_test_discovery_srcs/{module}.entries.swift".format(
                    module = symbol_graph.module_name,
                    target = name,
                ),
            )
            outputs.append(output_file)
            args.add(
                "--module-output",
                "{module}={path}".format(
                    module = symbol_graph.module_name,
                    path = output_file.path,
                ),
            )

        for symbol_graph in (
            symbol_graph_info.transitive_symbol_graphs.to_list()
        ):
            inputs.append(symbol_graph.symbol_graph_dir)

    # Also declare a single `main.swift` file where the discovery tool will
    # generate the main runner.
    main_file = actions.declare_file(
        "{target}_test_discovery_srcs/main.swift".format(target = name),
    )
    outputs.append(main_file)
    args.add("--main-output", main_file)

    # The discovery tool expects symbol graph directories as its inputs (it
    # iterates over their contents), so we must not expand directories here.
    args.add_all(inputs, expand_directories = False, uniquify = True)

    actions.run(
        arguments = [args],
        executable = test_discoverer,
        inputs = inputs,
        mnemonic = "SwiftTestDiscovery",
        outputs = outputs,
        progress_message = "Discovering tests for %{label}",
    )

    return outputs

def _swift_test_impl(ctx):
    swift_toolchain = ctx.attr._toolchain[SwiftToolchainInfo]

    feature_configuration = configure_features_for_binary(
        ctx = ctx,
        requested_features = ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = ctx.disabled_features,
    )

    is_bundled = swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_BUNDLED_XCTESTS,
    )

    # If we need to run the test in an .xctest bundle, the binary must have
    # Mach-O type `MH_BUNDLE` instead of `MH_EXECUTE`.
    extra_linkopts = ["-Wl,-bundle"] if is_bundled else []

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

    srcs = ctx.files.srcs

    # If no sources were provided and we're not using `.xctest` bundling, assume
    # that we need to discover tests using symbol graphs.
    # TODO(b/220945250): This supports SPM-style tests where each test target
    # (a separate module) maps to its own `swift_library`. We'll need to modify
    # this approach if we want to support test discovery for simple `swift_test`
    # targets that just write XCTest-style tests in the `srcs` directly.
    if not srcs and not is_bundled:
        srcs = _generate_test_discovery_srcs(
            actions = ctx.actions,
            deps = ctx.attr.deps,
            name = ctx.label.name,
            test_discoverer = ctx.executable._test_discoverer,
        )

    module_contexts = []
    all_supplemental_outputs = []

    if srcs:
        module_name = ctx.attr.module_name
        if not module_name:
            module_name = swift_common.derive_module_name(ctx.label)

        include_dev_srch_paths = include_developer_search_paths(ctx.attr)

        module_context, cc_compilation_outputs, supplemental_outputs = swift_common.compile(
            actions = ctx.actions,
            additional_inputs = ctx.files.swiftc_inputs,
            cc_infos = get_providers(ctx.attr.deps, CcInfo),
            copts = expand_locations(
                ctx,
                ctx.attr.copts,
                ctx.attr.swiftc_inputs,
            ) + _maybe_parse_as_library_copts(srcs),
            defines = ctx.attr.defines,
            extra_swift_infos = extra_swift_infos,
            feature_configuration = feature_configuration,
            include_dev_srch_paths = include_dev_srch_paths,
            module_name = module_name,
            objc_infos = get_providers(ctx.attr.deps, apple_common.Objc),
            package_name = ctx.attr.package_name,
            plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
            srcs = srcs,
            swift_infos = get_providers(ctx.attr.deps, SwiftInfo),
            swift_toolchain = swift_toolchain,
            target_name = ctx.label.name,
            workspace_name = ctx.workspace_name,
        )
        module_contexts.append(module_context)
        all_supplemental_outputs.append(supplemental_outputs)

        # Unlike `upstream`, we create a linking_context in order to support
        # `autolink-extract`. See `a1395155c6a27d76aab5e1a93455259a0ac10b2f` and
        # `93219a3b21390f212f5fd013e8db3654fd09814c`.
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
        cc_compilation_outputs = cc_common.create_compilation_outputs()

    additional_linking_contexts.append(malloc_linking_context(ctx))

    cc_feature_configuration = swift_common.cc_feature_configuration(
        feature_configuration = feature_configuration,
    )

    linking_outputs = register_link_binary_action(
        actions = ctx.actions,
        additional_inputs = ctx.files.swiftc_inputs,
        additional_linking_contexts = additional_linking_contexts,
        cc_feature_configuration = cc_feature_configuration,
        # This is already collected from `linking_context`.
        compilation_outputs = None,
        deps = ctx.attr.deps + extra_link_deps,
        name = ctx.label.name,
        output_type = "executable",
        owner = ctx.label,
        stamp = ctx.attr.stamp,
        swift_toolchain = swift_toolchain,
        user_link_flags = expand_locations(
            ctx,
            ctx.attr.linkopts,
            ctx.attr.swiftc_inputs,
        ) + extra_linkopts + ctx.fragments.cpp.linkopts,
    )

    # If the tests are to be bundled, create the bundle and the test runner
    # script that launches it via `xctest`. Otherwise, just use the binary
    # itself as the executable to launch.
    if is_bundled:
        xctest_bundle = _create_xctest_bundle(
            name = ctx.label.name,
            actions = ctx.actions,
            binary = linking_outputs.executable,
        )
        xctest_runner = _create_xctest_runner(
            name = ctx.label.name,
            actions = ctx.actions,
            bundle = xctest_bundle,
            xctest_runner_template = ctx.file._xctest_runner_template,
        )
        additional_test_outputs = [xctest_bundle]
        executable = xctest_runner
    else:
        additional_test_outputs = []
        executable = linking_outputs.executable

    test_environment = dicts.add(
        swift_toolchain.test_configuration.env,
        {"TEST_BINARIES_FOR_LLVM_COV": linking_outputs.executable.short_path},
        expanded_env.get_expanded_env(ctx, {}),
    )

    return [
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
        OutputGroupInfo(
            **supplemental_compilation_output_groups(
                *all_supplemental_outputs
            )
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        swift_common.create_swift_info(
            modules = [
                swift_common.create_module(
                    name = module_context.name,
                    compilation_context = module_context.compilation_context,
                    # The rest of the fields are intentionally ommited, as we
                    # only want to expose the compilation_context
                )
                for module_context in module_contexts
            ],
        ),
        testing.ExecutionInfo(
            swift_toolchain.test_configuration.execution_requirements,
        ),
        testing.TestEnvironment(test_environment),
    ]

swift_test = rule(
    attrs = dicts.add(
        binary_rule_attrs(
            additional_deps_aspects = [test_discovery_symbol_graph_aspect],
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
            "_test_discoverer": attr.label(
                cfg = "exec",
                default = Label(
                    "@build_bazel_rules_swift//tools/test_discoverer",
                ),
                executable = True,
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
