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

"""Implementation of the `swift_test` rule."""

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
    "@build_bazel_rules_swift//swift/internal:swift_symbol_graph_aspect.bzl",
    "SwiftTestDiscoverySymbolGraphInfo",
    "make_swift_symbol_graph_aspect",
)
load(
    "@build_bazel_rules_swift//swift/internal:symbol_graph_extracting.bzl",
    "extract_symbol_graph",
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
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":module_name.bzl", "derive_swift_module_name")
load(":providers.bzl", "SwiftBinaryInfo", "SwiftInfo")

visibility("public")

# Name of the execution group used for `SwiftTestDiscovery` actions.
_DISCOVER_TESTS_EXEC_GROUP = "discover_tests"

_test_discovery_symbol_graph_aspect = make_swift_symbol_graph_aspect(
    default_minimum_access_level = "internal",
    testonly_targets = True,
)

def _generate_test_discovery_srcs(
        *,
        actions,
        deps,
        name,
        objc_test_discovery,
        owner_module_name,
        owner_symbol_graph_dir = None,
        test_discoverer):
    """Generate Swift sources to run discovered XCTest-style tests.

    The `owner_module_name` and `owner_symbol_graph_dir` arguments are used to
    support discovery of tests from the sources of the `swift_test` target
    itself. If they are provided, then that symbol graph is used *instead of*
    the symbol graphs of the direct dependencies.

    Args:
        actions: The context's actions object.
        deps: The list of direct dependencies of the test target.
        name: The name of the target being built, which will be used to derive
            the basename of the directory containing the generated files.
        objc_test_discovery: If `True`, the runner should use Objective-C-based
            XCTest discovery instead of symbol graphs.
        owner_module_name: The name of the owner module (the target being
            built).
        owner_symbol_graph_dir: A directory-type `File` containing the extracted
            symbol graph for the owner target.
        test_discoverer: The executable `File` representing the test discoverer
            tool that will be spawned to generate the test runner sources.

    Returns:
        A list of `File`s representing generated `.swift` source files that
        should be compiled as part of the test target.
    """
    inputs = []
    outputs = []
    modules_to_scan = []
    args = actions.args()

    if objc_test_discovery:
        args.add("--objc-test-discovery")
    else:
        if owner_symbol_graph_dir:
            inputs.append(owner_symbol_graph_dir)
            modules_to_scan.append(owner_module_name)

        for dep in deps:
            if SwiftTestDiscoverySymbolGraphInfo not in dep:
                continue

            symbol_graph_info = (
                dep[SwiftTestDiscoverySymbolGraphInfo].symbol_graph_info
            )

            # Only include the direct symbol graphs if the owner didn't have any
            # sources.
            if not owner_symbol_graph_dir:
                modules_to_scan.extend([
                    symbol_graph.module_name
                    for symbol_graph in symbol_graph_info.direct_symbol_graphs
                ])

            # Always include the transitive symbol graphs; if a library depends
            # on a support class that inherits from `XCTestCase`, we need to be
            # able to detect that.
            for symbol_graph in (
                symbol_graph_info.transitive_symbol_graphs.to_list()
            ):
                inputs.append(symbol_graph.symbol_graph_dir)

        if not modules_to_scan:
            fail("Failed to find any modules to inspect for tests.")

        # For each direct dependency/module that we have a symbol graph for
        # (i.e., every testonly dependency), declare a `.swift` source file
        # where the discovery tool will generate an extension that lists the
        # test entries for the classes/methods found in that module.
        for module_name in modules_to_scan:
            output_file = actions.declare_file(
                "{target}_test_discovery_srcs/{module}.entries.swift".format(
                    module = module_name,
                    target = name,
                ),
            )
            outputs.append(output_file)
            args.add(
                "--module-output",
                "{module}={path}".format(
                    module = module_name,
                    path = output_file.path,
                ),
            )

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
        exec_group = _DISCOVER_TESTS_EXEC_GROUP,
        inputs = inputs,
        mnemonic = "SwiftTestDiscovery",
        outputs = outputs,
        progress_message = "Discovering tests for %{label}",
    )

    return outputs

def _do_compile(
        *,
        ctx,
        additional_copts = [],
        compilation_contexts,
        feature_configuration,
        module_name,
        name,
        plugins = [],
        srcs,
        swift_infos,
        toolchains):
    """Compiles Swift source code for a `swift_test` target.

    Args:
        ctx: The rule context.
        additional_copts: Additional Swift compiler options that should be used
            for this compilation action.
        compilation_contexts: A list of `CcCompilationContext`s that should be
            provided as inputs to the compilation action.
        feature_configuration: The feature configuration to use for compiling.
        module_name: The name of the module being compiled.
        name: The target name or a value derived from the target name that is
            used to name output files generated by the action.
        plugins: A list of `SwiftCompilerPluginInfo` providers that need to be
            loaded when compiling this module.
        srcs: The sources to compile.
        swift_infos: A list of `SwiftInfo` providers that should be used to
            determine the module inputs for the action.
        toolchains: The Swift and C++ toolchains to use to configure the build.

    Returns:
        The same value as would be returned by `compile`.
    """
    copts = expand_locations(ctx, ctx.attr.copts, ctx.attr.swiftc_inputs)
    c_copts = expand_locations(ctx, ctx.attr.c_copts, ctx.attr.swiftc_inputs)

    return compile(
        actions = ctx.actions,
        additional_inputs = ctx.files.swiftc_inputs,
        compilation_contexts = compilation_contexts,
        copts = copts + additional_copts,
        c_copts = c_copts,
        defines = ctx.attr.defines,
        feature_configuration = feature_configuration,
        module_name = module_name,
        plugins = plugins,
        srcs = srcs,
        swift_infos = swift_infos,
        toolchains = toolchains,
        target_name = name,
    )

def _swift_test_impl(ctx):
    toolchains = find_all_toolchains(ctx)
    feature_configuration = configure_features_for_binary(
        ctx = ctx,
        requested_features = ctx.features,
        toolchains = toolchains,
        unsupported_features = ctx.disabled_features,
    )

    discover_tests = ctx.attr.discover_tests
    objc_test_discovery = toolchains.swift.test_configuration.objc_test_discovery
    srcs = ctx.files.srcs
    owner_symbol_graph_dir = None

    deps = list(ctx.attr.deps)
    test_runner_deps = list(ctx.attr._test_runner_deps)

    # In test discovery mode (whether manual or by the Obj-C runtime), inject
    # the test observer that prints the xUnit-style output for Bazel. Otherwise
    # don't link this, because we don't want it to pull in link time
    # dependencies on XCTest, which the test binary may not be using.
    if discover_tests:
        additional_link_deps = test_runner_deps
    else:
        additional_link_deps = []

    # We also need to collect nested providers from `SwiftBinaryInfo` since we
    # support testing those.
    deps_compilation_contexts = []
    deps_swift_infos = []
    additional_linking_contexts = list(
        toolchains.swift.test_configuration.test_linking_contexts,
    )
    for dep in deps:
        if CcInfo in dep:
            deps_compilation_contexts.append(dep[CcInfo].compilation_context)
        if SwiftInfo in dep:
            deps_swift_infos.append(dep[SwiftInfo])
        if SwiftBinaryInfo in dep:
            binary_info = dep[SwiftBinaryInfo]
            deps_compilation_contexts.append(
                binary_info.cc_info.compilation_context,
            )
            deps_swift_infos.append(binary_info.swift_info)
            additional_linking_contexts.append(
                binary_info.cc_info.linking_context,
            )
    additional_linking_contexts.append(malloc_linking_context(ctx))

    test_runner_deps_compilation_contexts = get_compilation_contexts(
        test_runner_deps,
    )
    test_runner_deps_swift_infos = get_providers(test_runner_deps, SwiftInfo)

    module_name = ctx.attr.module_name
    if not module_name:
        module_name = derive_swift_module_name(
            ctx.label,
            feature_configuration = feature_configuration,
        )

    module_contexts = []
    all_supplemental_outputs = []

    if srcs:
        # If the `swift_test` target had sources, compile those first and then
        # extract a symbol graph from it.
        compile_result = _do_compile(
            ctx = ctx,
            # In test discovery mode (whether manual or by the Obj-C runtime),
            # compile the code with `-parse-as-library` to avoid the case where
            # a single file with no top-level code still produces an empty
            # `main`. Also compile with `-enable-testing`, because the generated
            # sources will `@testable import` this module, and this allows that
            # to work even when building in `-c opt` mode.
            additional_copts = [
                "-parse-as-library",
                "-enable-testing",
            ] if discover_tests else [],
            compilation_contexts = deps_compilation_contexts,
            feature_configuration = feature_configuration,
            module_name = module_name,
            name = ctx.label.name,
            plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
            srcs = srcs,
            swift_infos = deps_swift_infos,
            toolchains = toolchains,
        )

        module_contexts.append(compile_result.module_context)
        compilation_outputs = compile_result.compilation_outputs
        all_supplemental_outputs.append(compile_result.supplemental_outputs)

        swift_infos_including_owner = [compile_result.swift_info]

        # If we're going to do symbol-graph-based test discovery below, extract
        # the symbol graph of the module that we just compiled so that we can
        # discover any tests in the `srcs` of this target (instead of just in
        # the direct `deps`).
        if not objc_test_discovery:
            owner_symbol_graph_dir = ctx.actions.declare_directory(
                "{}.symbolgraphs".format(ctx.label.name),
            )
            extract_symbol_graph(
                actions = ctx.actions,
                compilation_contexts = deps_compilation_contexts,
                feature_configuration = feature_configuration,
                minimum_access_level = "internal",
                module_name = module_name,
                output_dir = owner_symbol_graph_dir,
                swift_infos = swift_infos_including_owner,
                toolchains = toolchains,
            )
    else:
        compilation_outputs = cc_common.create_compilation_outputs()
        swift_infos_including_owner = deps_swift_infos

    # If requested, discover tests and generate a runner for them.
    if discover_tests:
        discovery_srcs = _generate_test_discovery_srcs(
            actions = ctx.actions,
            deps = ctx.attr.deps,
            name = ctx.label.name,
            objc_test_discovery = objc_test_discovery,
            owner_module_name = module_name,
            owner_symbol_graph_dir = owner_symbol_graph_dir,
            test_discoverer = ctx.executable._test_discoverer,
        )
        discovery_compile_result = _do_compile(
            ctx = ctx,
            # The generated test runner uses `@main`.
            additional_copts = ["-parse-as-library"],
            compilation_contexts = test_runner_deps_compilation_contexts,
            feature_configuration = feature_configuration,
            module_name = module_name + "__GeneratedTestDiscoveryRunner",
            name = ctx.label.name + "__GeneratedTestDiscoveryRunner",
            srcs = discovery_srcs,
            swift_infos = (
                swift_infos_including_owner + test_runner_deps_swift_infos
            ),
            toolchains = toolchains,
        )
        module_contexts.append(discovery_compile_result.module_context)
        compilation_outputs = cc_common.merge_compilation_outputs(
            compilation_outputs = [
                compilation_outputs,
                discovery_compile_result.compilation_outputs,
            ],
        )
        all_supplemental_outputs.append(
            discovery_compile_result.supplemental_outputs,
        )

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

    binary_name = toolchains.swift.test_configuration.binary_name.replace(
        "{name}",
        ctx.label.name,
    )
    linking_outputs = register_link_binary_action(
        actions = ctx.actions,
        additional_inputs = ctx.files.swiftc_inputs,
        additional_linking_contexts = additional_linking_contexts,
        additional_outputs = additional_debug_outputs,
        compilation_outputs = compilation_outputs,
        deps = deps + additional_link_deps,
        feature_configuration = feature_configuration,
        label = ctx.label,
        module_contexts = module_contexts,
        name = binary_name,
        output_type = "executable",
        stamp = ctx.attr.stamp,
        toolchains = toolchains,
        user_link_flags = expand_locations(
            ctx,
            ctx.attr.linkopts,
            ctx.attr.swiftc_inputs,
        ) + ctx.fragments.cpp.linkopts,
        variables_extension = variables_extension,
    )

    test_environment = dicts.add(
        ctx.attr.env,
        toolchains.swift.test_configuration.env,
        {"TEST_BINARIES_FOR_LLVM_COV": linking_outputs.executable.short_path},
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
        OutputGroupInfo(
            **supplemental_compilation_output_groups(*all_supplemental_outputs)
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["deps"],
            extensions = ["swift"],
            source_attributes = ["srcs"],
        ),
        testing.ExecutionInfo(
            toolchains.swift.test_configuration.execution_requirements,
        ),
        RunEnvironmentInfo(
            environment = expand_locations(
                ctx,
                test_environment,
                ctx.attr.swiftc_inputs,
            ),
            inherited_environment = ctx.attr.env_inherit,
        ),
    ]

swift_test = rule(
    attrs = dicts.add(
        binary_rule_attrs(
            additional_deps_aspects = [_test_discovery_symbol_graph_aspect],
            additional_deps_providers = [[SwiftCompilerPluginInfo]],
            stamp_default = 0,
        ),
        {
            "discover_tests": attr.bool(
                default = True,
                doc = """\
Determines whether or not tests are automatically discovered in the binary. The
default value is `True`.

Tests are discovered in a platform-specific manner. On Apple platforms, they are
found using the XCTest framework's `XCTestSuite.default` accessor, which uses
the Objective-C runtime to dynamically discover tests. On non-Apple platforms,
discovery uses symbol graphs generated from dependencies to find classes and
methods written in XCTest's style.

If tests are discovered, then you should not provide your own `main` entry point
in the `swift_test` binary; the test runtime provides the entry point for you.
If you set this attribute to `False`, then you are responsible for providing
your own `main`. This allows you to write tests that use a framework other than
Apple's `XCTest`. The only requirement of such a test is that it terminate with
a zero exit code for success or a non-zero exit code for failure.
""",
                mandatory = False,
            ),
            "env_inherit": attr.string_list(
                doc = """\
Specifies additional environment variables to inherit from the external
environment when the test is executed by `bazel test`.
""",
            ),
            "_test_discoverer": attr.label(
                cfg = config.exec(_DISCOVER_TESTS_EXEC_GROUP),
                default = Label(
                    "@build_bazel_rules_swift//tools/test_discoverer",
                ),
                executable = True,
            ),
            "_test_runner_deps": attr.label_list(
                default = [
                    "@build_bazel_rules_swift//tools/test_observer",
                ],
            ),
        },
    ),
    doc = """\
Compiles and links Swift code into an executable test target.

### XCTest Test Discovery

By default, this rule performs _test discovery_ that finds tests written with
the `XCTest` framework and executes them automatically, without the user
providing their own `main` entry point.

On Apple platforms, `XCTest`-style tests are automatically discovered and
executed using the Objective-C runtime. To provide the same behavior on Linux,
the `swift_test` rule performs its own scan for `XCTest`-style tests. In other
words, you can write a single `swift_test` target that executes the same tests
on either Linux or Apple platforms.

There are two approaches that one can take to write a `swift_test` that supports
test discovery:

1.  **Preferred approach:** Write a `swift_test` target whose `srcs` contain
    your tests. In this mode, only these sources will be scanned for tests;
    direct dependencies will _not_ be scanned.

2.  Write a `swift_test` target with _no_ `srcs`. In this mode, all _direct_
    dependencies of the target will be scanned for tests; indirect dependencies
    will _not_ be scanned. This approach is useful if you want to share tests
    with an Apple-specific test target like `ios_unit_test`.

See the documentation of the `discover_tests` attribute for more information
about how this behavior affects the rule's outputs.

### Test Bundles

The `swift_test` rule always produces a standard executable binary. This is true
even when targeting macOS, where the typical practice is to use a Mach-O bundle
binary. However, when targeting macOS, the executable binary is still generated
inside a bundle-like directory structure: `{name}.xctest/Contents/MacOS/{name}`.
This allows tests to still work if they contain logic that looks for the path to
their bundle.

### Test Filtering

`swift_test` supports Bazel's `--test_filter` flag on all platforms (i.e., Apple
and Linux), which can be used to run only a subset of tests. The test filter can
be a test name of the form `ClassName/MethodName` or a regular expression that
matches names of that form.

For example,

*   `--test_filter='ArrayTests/testAppend'` would only run the test method
    `testAppend` in the `ArrayTests` class.
*   `--test_filter='ArrayTests/test(App.*|Ins.*)'` would run all test methods
    starting with `testApp` or `testIns` in the `ArrayTests` class.
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
        # Define an execution group for `SwiftTestDiscovery` actions that does
        # not have constraints, so that test discovery using the already
        # generated symbol graphs can be routed to any platform that supports it
        # (even one with a different toolchain).
        _DISCOVER_TESTS_EXEC_GROUP: exec_group(),
    },
    executable = True,
    fragments = ["cpp"],
    test = True,
    implementation = _swift_test_impl,
    toolchains = use_all_toolchains(),
)
