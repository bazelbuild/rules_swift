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

"""Implementation of compilation logic for Swift."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "@build_bazel_rules_swift//swift:module_name.bzl",
    "physical_swift_module_name",
)
load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftInfo",
    "create_clang_module_inputs",
    "create_swift_module_context",
    "create_swift_module_inputs",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(
    ":action_names.bzl",
    "SWIFT_ACTION_COMPILE",
    "SWIFT_ACTION_COMPILE_CODEGEN",
    "SWIFT_ACTION_COMPILE_MODULE",
    "SWIFT_ACTION_COMPILE_MODULE_INTERFACE",
    "SWIFT_ACTION_PRECOMPILE_C_MODULE",
)
load(":actions.bzl", "is_action_enabled", "run_toolchain_action")
load(":attrs.bzl", "C_HEADER_EXTENSIONS")
load(":explicit_module_map_file.bzl", "write_explicit_swift_module_map_file")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_COMPILE_IN_PARALLEL",
    "SWIFT_FEATURE_DECLARE_SWIFTSOURCEINFO",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
    "SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
    "SWIFT_FEATURE_MODULAR_INDEXING",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_CMO",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP",
    "SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__OPT_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__WMO_IN_SWIFTCOPTS",
)
load(
    ":features.bzl",
    "are_all_features_enabled",
    "get_cc_feature_configuration",
    "is_feature_enabled",
    "upcoming_and_experimental_features",
    "warnings_as_errors_from_features",
)
load(":module_maps.bzl", "write_module_map")
load(
    ":optimization.bzl",
    "find_num_threads_flag_value",
    "is_optimization_manually_requested",
    "is_wmo_manually_requested",
)
load(":toolchain_utils.bzl", "SWIFT_TOOLCHAIN_TYPE")
load(
    ":utils.bzl",
    "compact",
    "compilation_context_for_explicit_module_compilation",
    "get_clang_implicit_deps",
    "get_swift_implicit_deps",
    "merge_compilation_contexts",
    "owner_relative_path",
    "struct_fields",
)

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def compile_module_interface(
        *,
        actions,
        clang_module = None,
        compilation_contexts,
        copts = [],
        exec_group = None,
        feature_configuration,
        is_framework = False,
        module_name,
        swiftinterface_file,
        swift_infos,
        target_name,
        toolchains,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE):
    """Compiles a Swift module interface.

    Args:
        actions: The context's `actions` object.
        clang_module: An optional underlying Clang module (as returned by
            `create_clang_module_inputs`), if present for this Swift module.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        copts: A list of compiler flags that apply to the target being built.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        is_framework: True if this module is a Framework module, false othwerise.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `derive_swift_module_name` to generate a
            default from the target's label if needed.
        swiftinterface_file: The Swift module interface file to compile.
        swift_infos: A list of `SwiftInfo` providers from dependencies of the
            target being compiled.
        target_name: The name of the target for which the interface is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used
            for the proper selection of the execution platform inside
            `run_toolchain_action`.

    Returns:
        A `struct` with the following fields:

        *   `module_context`: A Swift module context (as returned by
            `create_swift_module_context`) that contains the Swift (and
            potentially C/Objective-C) compilation prerequisites of the compiled
            module. This should typically be propagated by a `SwiftInfo`
            provider of the calling rule, and the `CcCompilationContext` inside
            the Clang module substructure should be propagated by the `CcInfo`
            provider of the calling rule.

        *   `supplemental_outputs`: A `struct` representing supplemental,
            optional outputs. Its fields are:

            *   `indexstore_directory`: A directory-type `File` that represents
                the indexstore output files created when the feature
                `swift.index_while_building` is enabled.
    """
    swiftmodule_file = actions.declare_file(
        "{}_outs/{}.swiftmodule".format(target_name, module_name),
    )
    outputs = [swiftmodule_file]

    implicit_swift_infos, implicit_cc_infos = get_swift_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = toolchains.swift,
    )
    merged_compilation_context = merge_compilation_contexts(
        transitive_compilation_contexts = compilation_contexts + [
            cc_info.compilation_context
            for cc_info in implicit_cc_infos
        ],
    )
    merged_swift_info = SwiftInfo(
        swift_infos = swift_infos + implicit_swift_infos,
    )

    # Flattening this `depset` is necessary because we need to extract the
    # module maps or precompiled modules out of structured values and do so
    # conditionally. This should not lead to poor performance because the
    # flattening happens only once as the action is being registered, rather
    # than the same `depset` being flattened and re-merged multiple times up
    # the build graph.
    transitive_modules = merged_swift_info.transitive_modules.to_list()
    transitive_swiftmodules = []
    for module in transitive_modules:
        swift_module = module.swift
        if not swift_module:
            continue
        transitive_swiftmodules.append(swift_module.swiftmodule)

    if clang_module:
        transitive_modules.append(create_swift_module_context(
            name = module_name,
            clang = clang_module,
        ))

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP,
    ):
        explicit_swift_module_map_file = actions.declare_file(
            "{}.swift-explicit-module-map.json".format(module_name),
        )
        write_explicit_swift_module_map_file(
            actions = actions,
            explicit_swift_module_map_file = explicit_swift_module_map_file,
            module_contexts = transitive_modules,
        )
    else:
        explicit_swift_module_map_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
    ):
        indexstore_directory = actions.declare_directory(
            "{}.swiftinterface.indexstore".format(target_name),
        )
        outputs.append(indexstore_directory)
    else:
        indexstore_directory = None

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        explicit_swift_module_map_file = explicit_swift_module_map_file,
        genfiles_dir = feature_configuration._genfiles_dir,
        indexstore_directory = indexstore_directory,
        is_swift = True,
        module_name = module_name,
        source_files = [swiftinterface_file],
        swiftmodule_file = swiftmodule_file,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
        user_compile_flags = copts,
    )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = outputs,
        prerequisites = prerequisites,
        progress_message = "Compiling Swift module {} from textual interface".format(module_name),
        swift_toolchain = toolchains.swift,
        toolchain_type = toolchain_type,
    )

    module_context = create_swift_module_context(
        name = module_name,
        clang = clang_module or create_clang_module_inputs(
            compilation_context = merged_compilation_context,
            module_map = None,
        ),
        is_framework = is_framework,
        is_system = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_SYSTEM_MODULE,
        ),
        swift = create_swift_module_inputs(
            swiftdoc = None,
            swiftinterface = swiftinterface_file,
            swiftmodule = swiftmodule_file,
        ),
    )

    return struct(
        module_context = module_context,
        supplemental_outputs = struct(
            indexstore_directory = indexstore_directory,
        ),
    )

def compile(
        *,
        actions,
        additional_inputs = [],
        compilation_contexts,
        copts = [],
        c_copts = [],
        defines = [],
        exec_group = None,
        feature_configuration,
        generated_header_name = None,
        hdrs = [],
        module_name,
        plugins = [],
        private_compilation_contexts = [],
        private_swift_infos = [],
        srcs,
        swift_infos,
        toolchains,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
        target_name):
    """Compiles a Swift module.

    Args:
        actions: The context's `actions` object.
        additional_inputs: A list of `File`s representing additional input files
            that need to be passed to the Swift compile action because they are
            referenced by compiler flags.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        copts: A list of compiler flags that apply to the Swift sources in the
            target being built. These flags, along with those from Bazel's Swift
            configuration fragment (i.e., `--swiftcopt` command line flags) are
            scanned to determine whether whole module optimization is being
            requested, which affects the nature of the output files.
        c_copts: A list of compiler flags that apply to the C/Objective-C
            sources in the target being built.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        generated_header_name: The name of the Objective-C generated header that
            should be generated for this module. If omitted, no header will be
            generated.
        hdrs: A list of C/Objective-C header files that should be propagated by
            the module being compiled, if this is a mixed language module. Note
            that this should only contain *public* headers; private headers
            should be provided via `srcs`.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `derive_swift_module_name` to generate a
            default from the target's label if needed.
        plugins: A list of `SwiftCompilerPluginInfo` providers that represent
            plugins that should be loaded by the compiler.
        private_compilation_contexts: A list of `CcCompilationContext`s that
            represent private (non-propagated) C/Objective-C requirements of the
            target being compiled, such as Swift-compatible preprocessor
            defines, header search paths, and so forth. These are typically
            retrieved from the `CcInfo` providers of a target's `private_deps`.
        private_swift_infos: A list of `SwiftInfo` providers from private
            (implementation-only) dependencies of the target being compiled. The
            modules defined by these providers are used as dependencies of the
            Swift module being compiled but not of the Clang module for the
            generated header.
        srcs: The source files to compile. Typically this contains only Swift
            sources, but a mixed language module may contain C/Objective-C
            sources and private headers as well, and those will be compiled by
            the underlying C toolchain.
        swift_infos: A list of `SwiftInfo` providers from non-private
            dependencies of the target being compiled. The modules defined by
            these providers are used as dependencies of both the Swift module
            being compiled and the Clang module for the generated header.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used
            for the proper selection of the execution platform inside
            `run_toolchain_action`.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        A `struct` with the following fields:

        *   `swift_info`: A `SwiftInfo` provider whose list of direct modules
            contains the single Swift module context produced by this function
            (identical to the `module_context` field below) and whose transitive
            modules represent the transitive non-private dependencies. Rule
            implementations that call this function can typically return this
            provider directly, except in rare cases like making multiple calls
            to `swift_common.compile` that need to be merged.

        *   `module_context`: A Swift module context (as returned by
            `create_swift_module_context`) that contains the Swift (and
            potentially C/Objective-C) compilation prerequisites of the compiled
            module. This should typically be propagated by a `SwiftInfo`
            provider of the calling rule, and the `CcCompilationContext` inside
            the Clang module substructure should be propagated by the `CcInfo`
            provider of the calling rule.

        *   `compilation_outputs`: A `CcCompilationOutputs` object (as returned
            by `cc_common.create_compilation_outputs`) that contains the
            compiled object files.

        *   `supplemental_outputs`: A `struct` representing supplemental,
            optional outputs. Its fields are:

            *   `const_values_files`: A list of `File`s that contains JSON
                representations of constant values extracted from the source
                files, if requested via a direct dependency.

            *   `indexstore_directory`: A directory-type `File` that represents
                the indexstore output files created when the feature
                `swift.index_while_building` is enabled.

            *   `macro_expansion_directory`: A directory-type `File` that
                represents the location where macro expansion files were written
                (only in debug/fastbuild and only when the toolchain supports
                macros).
    """

    original_module_name = module_name
    module_alias = toolchains.swift.module_aliases.get(module_name)
    if module_alias:
        # If there was a module alias provided by a `swift_module_mapping`
        # rule, that takes precedence.
        module_name = module_alias
    else:
        physical_module_name = physical_swift_module_name(module_name)
        if physical_module_name != module_name:
            # If the derived physical module name is different from the provided
            # module name, then the provided name must not be identifier-safe.
            # We need to use the physical name as the actual module name and the
            # provided name as an alias.
            module_name = physical_module_name

    # These are the `SwiftInfo` providers that will be merged with the compiled
    # module context and returned as the `swift_info` field of this function's
    # result. Note that private deps are explicitly not included here, as they
    # are not supposed to be propagated.
    #
    # TODO(allevato): It would potentially clean things up if we included the
    # toolchain's implicit dependencies here as well. Do this and make sure it
    # doesn't break anything unexpected.
    swift_infos_to_propagate = swift_infos + _cross_imported_swift_infos(
        swift_toolchain = toolchains.swift,
        user_swift_infos = swift_infos + private_swift_infos,
    )

    implicit_swift_infos, implicit_cc_infos = get_swift_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = toolchains.swift,
    )
    all_swift_infos = (
        swift_infos_to_propagate + private_swift_infos + implicit_swift_infos
    )
    merged_swift_info = SwiftInfo(swift_infos = all_swift_infos)

    # Flattening this `depset` is necessary because we need to extract the
    # module maps or precompiled modules out of structured values and do so
    # conditionally. This should not lead to poor performance because the
    # flattening happens only once as the action is being registered, rather
    # than the same `depset` being flattened and re-merged multiple times up
    # the build graph.
    transitive_modules = merged_swift_info.transitive_modules.to_list()

    const_gather_protocols_file = _maybe_create_const_protocols_file(
        actions = actions,
        swift_infos = all_swift_infos,
        target_name = target_name,
    )

    compile_plan = _construct_compile_plan(
        srcs = srcs,
        hdrs = hdrs,
        actions = actions,
        extract_const_values = bool(const_gather_protocols_file),
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        module_name = module_name,
        target_name = target_name,
        user_compile_flags = copts,
    )
    compile_outputs = compile_plan.outputs

    transitive_swiftmodules = []
    defines_set = set(defines)
    for module in transitive_modules:
        swift_module = module.swift
        if not swift_module:
            continue
        transitive_swiftmodules.append(swift_module.swiftmodule)
        if swift_module.defines:
            defines_set.update(swift_module.defines)

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP,
    ):
        # Generate the JSON file that contains the manifest of Swift
        # dependencies.
        explicit_swift_module_map_file = actions.declare_file(
            "{}.swift-explicit-module-map.json".format(target_name),
        )
        write_explicit_swift_module_map_file(
            actions = actions,
            explicit_swift_module_map_file = explicit_swift_module_map_file,
            module_contexts = transitive_modules,
        )
    else:
        explicit_swift_module_map_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_LAYERING_CHECK_SWIFT,
    ):
        # For performance, don't worry about uniquing the module names; since
        # Bazel doesn't allow repeated `deps` the only time a duplicate might
        # appear is if someone explicitly depends on an implicit dependency that
        # came from the toolchain. This is relatively unlikely, and the worker
        # will dedupe it anyway.
        direct_module_names = []
        for dep_swift_info in all_swift_infos:
            for dep_module_context in dep_swift_info.direct_modules:
                direct_module_names.append(dep_module_context.name)

        deps_modules_file = actions.declare_file(
            "{}.deps-module-mapping".format(target_name),
        )
        _write_deps_modules_file(
            actions = actions,
            deps_modules_file = deps_modules_file,
            direct_module_names = direct_module_names,
        )
    else:
        deps_modules_file = None

    # As of the time of this writing (Xcode 15.0), macros are the only kind of
    # plugins that are available. Since macros do source-level transformations,
    # we only need to load plugins directly used by the module being compiled.
    # Plugins that are only used by transitive dependencies do *not* need to be
    # passed; the compiler does not attempt to load them when deserializing
    # modules.
    used_plugins = list(plugins)
    for swift_info in all_swift_infos:
        for module_context in swift_info.direct_modules:
            if module_context.swift and module_context.swift.plugins:
                used_plugins.extend(module_context.swift.plugins)

    upcoming_features, experimental_features = upcoming_and_experimental_features(
        feature_configuration = feature_configuration,
    )
    warnings_as_errors = warnings_as_errors_from_features(
        feature_configuration = feature_configuration,
    )

    # In order to support mixed language modules, we need to perform multiple
    # compilation steps:
    #
    # 1.  If any C/Objective-C headers were provided, compile a Clang module
    #     containing them.
    # 2.  Compile the Swift sources into a Swift module, which will take the
    #     module from step 1 among its dependencies.
    # 3.  If step 2 generated a C/Objective-C header, compile another Clang
    #     module containing that header, along with the other C headers that
    #     were present in step 1. This will be propagated to this target's
    #     dependents.
    # 4.  Compile any C/Objective-C sources that were provided, if any, using
    #     the compilation context from step 3.

    # `cc_common.create_compilation_context` doesn't provide a way for us to
    # distinguish public vs. private headers, but calling `cc_common.compile`
    # (via `_compile_c_inputs`) to "compile" the headers does let us do this.

    # Step 1
    incomplete_compilation_context, _ = _compile_c_inputs(
        actions = actions,
        compilation_contexts = compilation_contexts,
        copts = c_copts,
        defines = defines,
        feature_configuration = feature_configuration,
        private_hdrs = compile_plan.c_inputs.private_hdrs,
        public_hdrs = compile_plan.c_inputs.public_hdrs,
        srcs = [],
        swift_infos = swift_infos,
        toolchains = toolchains,
        target_name = "{}.incomplete".format(target_name),
    )
    incomplete_header_module = _compile_clang_module_for_swift_module(
        actions = actions,
        compilation_context = incomplete_compilation_context,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        is_incomplete_header_module = bool(generated_header_name),
        is_swift_generated_header = False,
        module_name = module_name,
        # If we're generating a header for this Swift module, defer indexing to
        # when we generate the full module that includes that header as well.
        # Otherwise, this is the only Clang module that we're compiling, so we
        # need to index it now.
        should_index = not generated_header_name,
        swift_infos = swift_infos,
        toolchains = toolchains,
        target_name = target_name,
        toolchain_type = toolchain_type,
    )

    merged_compilation_context = merge_compilation_contexts(
        direct_compilation_contexts = [incomplete_compilation_context],
        transitive_compilation_contexts = (
            private_compilation_contexts + [
                cc_info.compilation_context
                for cc_info in implicit_cc_infos
            ]
        ),
    )

    prerequisites = {
        "additional_inputs": additional_inputs,
        "always_include_headers": is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS,
        ),
        "bin_dir": feature_configuration._bin_dir,
        "cc_compilation_context": merged_compilation_context,
        "const_gather_protocols_file": const_gather_protocols_file,
        "defines": list(defines_set),
        "deps_modules_file": deps_modules_file,
        "experimental_features": experimental_features,
        "explicit_swift_module_map_file": explicit_swift_module_map_file,
        "genfiles_dir": feature_configuration._genfiles_dir,
        "is_swift": True,
        "mixed_module_clang_inputs": incomplete_header_module,
        "module_name": module_name,
        "original_module_name": original_module_name,
        "plugins": used_plugins,
        "source_files": compile_plan.swift_inputs.srcs,
        "target_label": feature_configuration._label,
        "transitive_modules": transitive_modules,
        "transitive_swiftmodules": transitive_swiftmodules,
        "upcoming_features": upcoming_features,
        "user_compile_flags": copts,
        "warnings_as_errors": warnings_as_errors,
    } | struct_fields(compile_outputs)

    # Step 2
    if _should_plan_parallel_compilation(
        feature_configuration = feature_configuration,
        user_compile_flags = copts,
    ):
        _execute_compile_plan(
            actions = actions,
            compile_plan = compile_plan,
            exec_group = exec_group,
            feature_configuration = feature_configuration,
            prerequisites = prerequisites,
            swift_toolchain = toolchains.swift,
            toolchain_type = toolchain_type,
        )
    else:
        _plan_legacy_swift_compilation(
            actions = actions,
            compile_outputs = compile_plan.outputs,
            exec_group = exec_group,
            feature_configuration = feature_configuration,
            prerequisites = prerequisites,
            swift_toolchain = toolchains.swift,
            toolchain_type = toolchain_type,
        )

    # Steps 3 and 4
    c_compilation_context, c_compilation_outputs = _compile_c_inputs(
        actions = actions,
        compilation_contexts = compilation_contexts,
        copts = c_copts,
        defines = defines,
        feature_configuration = feature_configuration,
        has_generated_header = bool(compile_outputs.generated_header_file),
        private_hdrs = compile_plan.c_inputs.private_hdrs,
        public_hdrs = compile_plan.c_inputs.public_hdrs + compact([
            compile_outputs.generated_header_file,
        ]),
        srcs = compile_plan.c_inputs.srcs,
        swift_infos = swift_infos,
        toolchains = toolchains,
        target_name = target_name,
    )
    if generated_header_name:
        merged_compilation_context = merge_compilation_contexts(
            direct_compilation_contexts = [c_compilation_context],
            transitive_compilation_contexts = (
                private_compilation_contexts + [
                    cc_info.compilation_context
                    for cc_info in implicit_cc_infos
                ]
            ),
        )
        generated_header_module = _compile_clang_module_for_swift_module(
            actions = actions,
            compilation_context = c_compilation_context,
            exec_group = exec_group,
            feature_configuration = feature_configuration,
            is_incomplete_header_module = False,
            is_swift_generated_header = True,
            module_name = module_name,
            should_index = True,
            swift_infos = (
                swift_infos +
                toolchains.swift.generated_header_module_implicit_deps_providers.swift_infos
            ),
            toolchains = toolchains,
            target_name = target_name,
            toolchain_type = toolchain_type,
        )
    else:
        generated_header_module = incomplete_header_module

    module_context = create_swift_module_context(
        name = module_name,
        clang = create_clang_module_inputs(
            compilation_context = c_compilation_context,
            module_map = generated_header_module.module_map_file,
            precompiled_module = generated_header_module.precompiled_module,
        ),
        is_system = False,
        source_name = original_module_name,
        swift = create_swift_module_inputs(
            defines = defines,
            plugins = plugins,
            swiftdoc = compile_outputs.swiftdoc_file,
            swiftinterface = compile_outputs.swiftinterface_file,
            swiftmodule = compile_outputs.swiftmodule_file,
            swiftsourceinfo = compile_outputs.swiftsourceinfo_file,
        ),
    )

    compilation_outputs = cc_common.merge_compilation_outputs(
        compilation_outputs = [
            cc_common.create_compilation_outputs(
                objects = depset(compile_outputs.object_files),
                pic_objects = depset(compile_outputs.object_files),
            ),
            c_compilation_outputs,
        ],
    )

    return struct(
        module_context = module_context,
        compilation_outputs = compilation_outputs,
        supplemental_outputs = struct(
            const_values_files = compile_outputs.const_values_files,
            indexstore_directory = compile_outputs.indexstore_directory,
            macro_expansion_directory = (
                compile_outputs.macro_expansion_directory
            ),
        ),
        swift_info = SwiftInfo(
            modules = [module_context],
            swift_infos = swift_infos_to_propagate,
        ),
    )

def _should_plan_parallel_compilation(
        feature_configuration,
        user_compile_flags):
    """Returns `True` if the compilation should be done in parallel."""
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_COMPILE_IN_PARALLEL,
    ):
        return False

    # When the Swift driver plans a compilation, the default behavior is to emit
    # separate frontend jobs to emit the module and to perform codegen. However,
    # this will *not* happen if cross-module optimization is possible; in that
    # case, the driver emits a single frontend job to compile everything. If any
    # of the following conditions is true, then cross-module optimization is not
    # possible and we can plan parallel compilation:
    #
    # -   Whole-module optimization is not enabled.
    # -   Library evolution is enabled.
    # -   Cross-module optimization has been explicitly disabled.
    # -   Optimization (via the `-O` flag group) has not been requested.
    #
    # This logic mirrors that defined in
    # https://github.com/swiftlang/swift-driver/blob/c647e91574122f2b104d294ab1ec5baadaa1aa95/Sources/SwiftDriver/Jobs/EmitModuleJob.swift#L156-L181.
    if not (
        is_wmo_manually_requested(
            user_compile_flags = user_compile_flags,
        ) or are_all_features_enabled(
            feature_configuration = feature_configuration,
            feature_names = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ) or is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE__WMO_IN_SWIFTCOPTS,
        )
    ):
        return True

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION,
    ):
        return True

    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OPT_USES_CMO,
    ):
        return True

    return (
        not is_optimization_manually_requested(
            user_compile_flags = user_compile_flags,
        ) and not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_OPT,
        ) and not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE__OPT_IN_SWIFTCOPTS,
        )
    )

def _execute_compile_plan(
        actions,
        compile_plan,
        exec_group,
        feature_configuration,
        prerequisites,
        swift_toolchain,
        toolchain_type):
    """Executes the planned actions needed to compile a Swift module.

    Args:
        actions: The context's `actions` object.
        compile_plan: A `struct` containing information about the planned
            compilation actions.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        prerequisites: A `dict` containing the common prerequisites for the
            compilation action.
        swift_toolchain: The Swift toolchain being used to build.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used
            for the proper selection of the execution platform inside
            `run_toolchain_action`.
    """
    compile_outputs = compile_plan.outputs
    module_outputs = compact([
        # We put the module file first so that any generated command line files
        # will be named after it. This output will always exist so the names
        # will be predictable.
        compile_plan.module_outputs.swiftmodule_file,
        compile_plan.module_outputs.generated_header_file,
        compile_plan.module_outputs.macro_expansion_directory,
        compile_plan.module_outputs.swiftdoc_file,
        compile_plan.module_outputs.swiftinterface_file,
        compile_plan.module_outputs.swiftsourceinfo_file,
    ])

    module_prereqs = dict(prerequisites)
    module_prereqs["compile_step"] = struct(
        action = SWIFT_ACTION_COMPILE_MODULE,
        output = compile_outputs.swiftmodule_file.path,
    )
    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_COMPILE_MODULE,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = module_outputs,
        prerequisites = struct(**module_prereqs),
        progress_message = "Compiling Swift module {}".format(
            prerequisites["module_name"],
        ),
        swift_toolchain = swift_toolchain,
        toolchain_type = toolchain_type,
    )

    batches = _compute_codegen_batches(
        batch_size = swift_toolchain.codegen_batch_size,
        compile_plan = compile_plan,
        feature_configuration = feature_configuration,
    )
    for number, batch in enumerate(batches, 1):
        object_prereqs = dict(prerequisites)

        # If there is only one batch (for small libraries, or libraries of any
        # size compiled with whole-module optimization), we omit the requested
        # file paths to eliminate some unneeded work in the worker. It will
        # treat a blank value as "emit all outputs".
        if len(batches) == 1:
            step_detail = ""
        else:
            step_detail = ",".join([
                object.path
                for invocation in batch
                for object in invocation.objects
            ])
        object_prereqs["compile_step"] = struct(
            action = SWIFT_ACTION_COMPILE_CODEGEN,
            output = step_detail,
        )

        batch_suffix = ""
        if compile_plan.output_nature.emits_multiple_objects:
            batch_suffix = " ({} of {})".format(number, len(batches))
        progress_message = "Codegen for Swift module {}{}".format(
            prerequisites["module_name"],
            batch_suffix,
        )

        batch_outputs = [
            output
            for invocation in batch
            for output in invocation.objects + invocation.other_outputs
        ]
        if is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
        ):
            # TODO: b/351801556 - If this is true, then we only have one batch
            # (`_compute_codegen_batches` ensures this). Indexing happens when
            # object files are emitted, so we need to declare that output here.
            # Update the APIs to support multiple indexstore directories per
            # target so that we can emit one indexstore per batch instead.
            batch_outputs.append(compile_plan.outputs.indexstore_directory)

        run_toolchain_action(
            actions = actions,
            action_name = SWIFT_ACTION_COMPILE_CODEGEN,
            exec_group = exec_group,
            feature_configuration = feature_configuration,
            outputs = batch_outputs,
            prerequisites = struct(**object_prereqs),
            progress_message = progress_message,
            swift_toolchain = swift_toolchain,
            toolchain_type = toolchain_type,
        )

def _compute_codegen_batches(
        batch_size,
        compile_plan,
        feature_configuration):
    """Computes the batches of object files that will be compiled.

    Args:
        batch_size: The number of source files to compile in each batch.
        compile_plan: A `struct` containing information about the planned
            compilation actions.
        feature_configuration: The feature configuration for the target being
            compiled.

    Returns:
        A list of batches. Each batch itself is a list, where each element is a
        struct that specifies the outputs for a particular codegen invocation
        to be registered.
    """
    codegen_outputs = compile_plan.codegen_outputs
    codegen_count = len(codegen_outputs)

    # TODO: b/351801556 - Update the APIs to support multiple indexstore
    # directories per target so that we can emit one indexstore per batch. For
    # now, force one batch if indexing is enabled.
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
    ):
        return [codegen_outputs]

    batch_count = codegen_count // batch_size

    # Make sure to round up if we have a partial batch left over.
    if codegen_count % batch_size != 0:
        batch_count += 1

    batches = []
    for batch_index in range(batch_count):
        batch_start = batch_index * batch_size
        batch_end = min(batch_start + batch_size, codegen_count)
        batches.append(codegen_outputs[batch_start:batch_end])
    return batches

def _plan_legacy_swift_compilation(
        actions,
        compile_outputs,
        exec_group,
        feature_configuration,
        prerequisites,
        swift_toolchain,
        toolchain_type):
    """Plans the single driver invocation needed to compile a Swift module.

    The legacy compilation mode uses a single driver invocation to compile both
    the `.swiftmodule` file and the object files.

    Args:
        actions: The context's `actions` object.
        compile_outputs: A `struct` containing the registered outputs of the
            compilation action.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        prerequisites: A `dict` containing the common prerequisites for the
            compilation action.
        swift_toolchain: The Swift toolchain being used to build.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used
            for the proper selection of the execution platform inside
            `run_toolchain_action`.
    """
    all_compile_outputs = compact([
        # The `.swiftmodule` file is explicitly listed as the first output
        # because it will always exist and because Bazel uses it as a key for
        # various things (such as the filename prefix for param files generated
        # for that action). This guarantees some predictability.
        compile_outputs.swiftmodule_file,
        compile_outputs.swiftdoc_file,
        compile_outputs.swiftinterface_file,
        compile_outputs.swiftsourceinfo_file,
        compile_outputs.generated_header_file,
        compile_outputs.indexstore_directory,
        compile_outputs.macro_expansion_directory,
    ]) + compile_outputs.object_files + compile_outputs.const_values_files

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_COMPILE,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = all_compile_outputs,
        prerequisites = struct(**prerequisites),
        progress_message = "Compiling Swift module {}".format(
            prerequisites["module_name"],
        ),
        swift_toolchain = swift_toolchain,
        toolchain_type = toolchain_type,
    )

def _compile_clang_module_for_swift_module(
        actions,
        compilation_context,
        exec_group,
        feature_configuration,
        is_incomplete_header_module,
        is_swift_generated_header,
        module_name,
        should_index,
        swift_infos,
        toolchains,
        target_name,
        toolchain_type):
    """Precompiles the Clang module for the Swift module being compiled.

    Args:
        actions: The context's `actions` object.
        compilation_context: A `CcCompilationContext` that represents the
            compilation requirements for the C/Objective-C part of this Swift
            module; that is, the module's own public/private headers as well as
            the transitive headers needed to successfully compile it.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        is_incomplete_header_module: If True, the module is an "incomplete"
            header module that does not contain the generated header (and more
            specifically, there will be a second module compiled that does
            include it).
        is_swift_generated_header: If True, the module contains the Swift
            generated header.
        module_name: The name of the module being compiled.
        should_index: If True and index-while-building is enabled, the
            indexstore directory should be declared and returned among the
            results.
        swift_infos: The `SwiftInfo` providers for the dependencies of this
            module.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used
            for the proper selection of the execution platform inside
            `run_toolchain_action`.

    Returns:
        A `struct` (never `None`) containing the following fields:

        *   `module_name`: The name of the Clang module. This may be `None` if
            no generated header was requested.
        *   `module_map_file`: The module map file that defines the Clang module
            for the Swift generated header. This may be `None` if no generated
            header was requested.
        *   `precompiled_module`: The precompiled module that contains the
            compiled Clang module. This may be `None` if explicit modules are
            not enabled.
        *   `vfs_overlay_file`: A VFS overlay file that pretends that the
            module map and precompiled module are at the same location as the
            incomplete module map and precompiled module. This may be `None` if
            the module is not an incomplete header module.
        *   `virtual_module_map_path`: The virtual path of the module map file
            in the VFS overlay. This may be `None` if the module is not an
            incomplete header module.
        *   `virtual_precompiled_module_path`: The virtual path of the precompiled
            module in the VFS overlay. This may be `None` if the module is not
            an incomplete header module or explicit modules are not enabled.
    """
    if (
        not compilation_context.direct_public_headers and
        not compilation_context.direct_private_headers
    ):
        return struct(
            module_name = None,
            module_map_file = None,
            precompiled_module = None,
            vfs_overlay_file = None,
            virtual_module_map_path = None,
            virtual_precompiled_module_path = None,
        )

    # Collect the `SwiftInfo` providers that represent the dependencies of the
    # Objective-C generated header module -- this includes the dependencies of
    # the Swift module, plus any additional dependencies that the toolchain says
    # are required for all generated header modules.
    dependent_module_names = set()
    for swift_info in swift_infos:
        for module in swift_info.direct_modules:
            if module.clang:
                dependent_module_names.add(module.name)

    file_extension_fragment = (
        ".incomplete" if is_incomplete_header_module else ""
    )
    generated_module_map = actions.declare_file(
        "{}.swift{}.modulemap".format(target_name, file_extension_fragment),
    )
    write_module_map(
        actions = actions,
        dependent_module_names = sorted(dependent_module_names),
        module_map_file = generated_module_map,
        module_name = module_name,
        private_headers = compilation_context.direct_private_headers,
        public_headers = compilation_context.direct_public_headers,
        workspace_relative = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
        ),
    )

    compilation_context_to_compile = (
        compilation_context_for_explicit_module_compilation(
            compilation_contexts = [compilation_context],
            swift_infos = swift_infos,
        )
    )
    pcm_outputs = _precompile_clang_module(
        actions = actions,
        cc_compilation_context = compilation_context_to_compile,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        file_extension = "{}.pcm".format(file_extension_fragment),
        is_swift_generated_header = is_swift_generated_header,
        module_map_file = generated_module_map,
        module_name = module_name,
        should_index = should_index,
        swift_infos = swift_infos,
        toolchains = toolchains,
        target_name = target_name,
        toolchain_type = toolchain_type,
    )
    if pcm_outputs:
        precompiled_module = pcm_outputs.pcm_file
    else:
        precompiled_module = None

    # If this is an incomplete header module, we need to mimic Xcode's behavior
    # and create a VFS overlay that pretends that the incomplete module map and
    # precompiled module are actually at the same location that the complete
    # ones will be. This is because the paths to the module map and precompiled
    # module will be serialized into the `.swiftmodule` file, and we need them
    # to look the same as what downstream dependents will use. Otherwise, LLDB
    # will attempt to load both the incomplete and the complete modules, which
    # will fail because they will be treated as duplicates.
    #
    # This depends on some extremely specific logic in the Swift frontend that
    # checks the name of the VFS overlay and avoids serializing it:
    # https://github.com/swiftlang/swift/blob/454e5ea98fde61c33d522f2f09aeb20736ba7b07/lib/Serialization/Serialization.cpp#L1203-L1221
    vfs_overlay_file = None
    virtual_module_map_path = None
    virtual_precompiled_module_path = None
    if is_incomplete_header_module:
        vfs_dir_path = generated_module_map.dirname
        virtual_module_map_basename = "{}.swift.modulemap".format(target_name)
        virtual_module_map_path = paths.join(
            vfs_dir_path,
            virtual_module_map_basename,
        )

        vfs_contents = [
            {
                "type": "file",
                "name": virtual_module_map_basename,
                "external-contents": generated_module_map.path,
            },
        ]
        if precompiled_module:
            virtual_precompiled_module_basename = "{}.swift.pcm".format(
                target_name,
            )
            virtual_precompiled_module_path = paths.join(
                vfs_dir_path,
                virtual_precompiled_module_basename,
            )
            vfs_contents.append({
                "type": "file",
                "name": virtual_precompiled_module_basename,
                "external-contents": precompiled_module.path,
            })

        incomplete_module_overlay = {
            "version": 0,
            "case-sensitive": True,
            "roots": [
                {
                    "type": "directory",
                    "name": vfs_dir_path,
                    "contents": vfs_contents,
                },
            ],
        }
        vfs_overlay_file = actions.declare_file(
            "{}_objs/unextended-module-overlay.yaml".format(target_name),
        )
        actions.write(
            content = json.encode(incomplete_module_overlay),
            output = vfs_overlay_file,
        )

    return struct(
        module_name = module_name,
        module_map_file = generated_module_map,
        precompiled_module = precompiled_module,
        vfs_overlay_file = vfs_overlay_file,
        virtual_module_map_path = virtual_module_map_path,
        virtual_precompiled_module_path = virtual_precompiled_module_path,
    )

def precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        exec_group = None,
        feature_configuration,
        module_map_file,
        module_name,
        target_name,
        toolchains,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
        swift_infos = []):
    """Precompiles an explicit Clang module that is compatible with Swift.

    Args:
        actions: The context's `actions` object.
        cc_compilation_context: A `CcCompilationContext` that contains headers
            and other information needed to compile this module. This
            compilation context should contain all headers required to compile
            the module, which includes the headers for the module itself *and*
            any others that must be present on the file system/in the sandbox
            for compilation to succeed. The latter typically refers to the set
            of headers of the direct dependencies of the module being compiled,
            which Clang needs to be physically present before it detects that
            they belong to one of the precompiled module dependencies.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used for
            the proper selection of the execution platform inside `run_toolchain_action`.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.

    Returns:
        A struct containing the precompiled module and optional indexstore directory,
        or `None` if the toolchain or target does not support precompiled modules.
    """
    return _precompile_clang_module(
        actions = actions,
        cc_compilation_context = cc_compilation_context,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        file_extension = ".pcm",
        is_swift_generated_header = False,
        module_map_file = module_map_file,
        module_name = module_name,
        should_index = True,
        swift_infos = swift_infos,
        target_name = target_name,
        toolchains = toolchains,
        toolchain_type = toolchain_type,
    )

def _precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        exec_group = None,
        feature_configuration,
        file_extension,
        is_swift_generated_header,
        module_map_file,
        module_name,
        should_index,
        swift_infos = [],
        toolchains,
        toolchain_type,
        target_name):
    """Precompiles an explicit Clang module that is compatible with Swift.

    Args:
        actions: The context's `actions` object.
        cc_compilation_context: A `CcCompilationContext` that contains headers
            and other information needed to compile this module. This
            compilation context should contain all headers required to compile
            the module, which includes the headers for the module itself *and*
            any others that must be present on the file system/in the sandbox
            for compilation to succeed. The latter typically refers to the set
            of headers of the direct dependencies of the module being compiled,
            which Clang needs to be physically present before it detects that
            they belong to one of the precompiled module dependencies.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        file_extension: The file extension of the generated precompiled module.
        is_swift_generated_header: If True, the action is compiling the
            Objective-C header generated by the Swift compiler for a module.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        should_index: If True and index-while-building is enabled, the
            indexstore directory should be declared and returned among the
            results.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used for
            the proper selection of the execution platform inside `run_toolchain_action`.

    Returns:
        A struct containing the precompiled module and optional indexstore directory,
        or `None` if the toolchain or target does not support precompiled modules.
    """

    # Exit early if the toolchain does not support precompiled modules or if the
    # feature configuration for the target being built does not want a module to
    # be emitted.
    if not is_action_enabled(
        action_name = SWIFT_ACTION_PRECOMPILE_C_MODULE,
        toolchains = toolchains,
    ):
        return None
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_C_MODULE,
    ):
        return None

    precompiled_module = actions.declare_file(
        "{}.swift{}".format(target_name, file_extension),
    )

    if not is_swift_generated_header:
        implicit_swift_infos, implicit_cc_infos = get_clang_implicit_deps(
            feature_configuration = feature_configuration,
            swift_toolchain = toolchains.swift,
        )
        cc_compilation_context = merge_compilation_contexts(
            direct_compilation_contexts = [cc_compilation_context],
            transitive_compilation_contexts = [
                cc_info.compilation_context
                for cc_info in implicit_cc_infos
            ],
        )
    else:
        implicit_swift_infos, implicit_cc_infos = [], []

    if not is_swift_generated_header and implicit_swift_infos:
        swift_infos = list(swift_infos)
        swift_infos.extend(implicit_swift_infos)

    if swift_infos:
        merged_swift_info = SwiftInfo(swift_infos = swift_infos)
        transitive_modules = merged_swift_info.transitive_modules.to_list()
    else:
        transitive_modules = []

    outputs = [precompiled_module]
    if should_index and are_all_features_enabled(
        feature_configuration = feature_configuration,
        feature_names = [
            SWIFT_FEATURE_INDEX_WHILE_BUILDING,
            SWIFT_FEATURE_MODULAR_INDEXING,
            SWIFT_FEATURE_SYSTEM_MODULE,
        ],
    ):
        indexstore_directory = actions.declare_directory(
            "{}.swift.pcm.indexstore".format(target_name),
        )
        outputs.append(indexstore_directory)
        index_unit_output_path = precompiled_module.path
    else:
        indexstore_directory = None
        index_unit_output_path = None

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = compilation_context_for_explicit_module_compilation(
            compilation_contexts = [cc_compilation_context],
            swift_infos = swift_infos,
        ),
        genfiles_dir = feature_configuration._genfiles_dir,
        indexstore_directory = indexstore_directory,
        index_unit_output_path = index_unit_output_path,
        is_swift = False,
        is_swift_generated_header = is_swift_generated_header,
        module_name = module_name,
        pcm_file = precompiled_module,
        source_files = [module_map_file],
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
    )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_PRECOMPILE_C_MODULE,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = outputs,
        prerequisites = prerequisites,
        progress_message = "Precompiling C module {}".format(module_name),
        swift_toolchain = toolchains.swift,
        toolchain_type = toolchain_type,
    )

    return struct(
        indexstore_directory = indexstore_directory,
        pcm_file = precompiled_module,
    )

def _compile_c_inputs(
        *,
        actions,
        compilation_contexts,
        copts,
        defines,
        feature_configuration,
        has_generated_header = False,
        private_hdrs,
        public_hdrs,
        srcs,
        swift_infos,
        toolchains,
        target_name):
    """Compiles the C/Objective-C inputs for a Swift module, if any.

    The returned compilation context contains the generated Objective-C header
    for the module (if any), along with any preprocessor defines based on
    compilation settings passed to the Swift compilation.

    Args:
        actions: The context's `actions` object.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        copts: A list of flags that will be passed to the C/Objective-C
            compiler.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        has_generated_header: If True, the `public_hdrs` include a generated
            Objective-C header.
        private_hdrs: Private headers that should be used when compiling the
            C/Objective-C sources.
        public_hdrs: Public headers that should be propagated by the new
            compilation context (for example, the module's generated header).
        srcs: C/Objective-C source files that should be compiled, if this is a
            mixed-language module.
        swift_infos: A list of `SwiftInfo` providers from regular and private
            dependencies of the target being compiled. This is used to retrieve
            any strict include paths that should be used during Objective-C
            compilation but not propagated.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        A tuple containing two values:

        1.  The `CcCompilationContext` that should be propagated by the calling
            target.
        2.  A `CcCompilationOutputs` that should be merged with the object files
            obtained by compiling the Swift code in the same target.
    """

    # If we have any C/Objective-C inputs, we need to call `cc_common.compile`.
    # Even if we only have headers, this is necessary to get the correct
    # compilation context, because it gives the C++/Objective-C logic in Bazel
    # an opportunity to register its own actions relevant to the headers, like
    # creating a layering check module map. Without this, Swift targets won't be
    # treated as `use`d modules when generating the layering check module map
    # for an `objc_library`, and those layering checks will fail when the
    # Objective-C code tries to import the `swift_library`'s headers.
    if private_hdrs or public_hdrs or srcs:
        language = toolchains.swift.cc_language
        variables_extension = {}
        if language == "objc":
            # This is required to enable ARC when compiling Objective-C code.
            # We do not support non-ARC compilation in Swift mixed modules.
            variables_extension["objc_arc"] = ""

        # If we have a generated header, we need to create the feature
        # configuration that disables `parse_headers` for the compilation
        # action.
        if has_generated_header:
            cc_feature_configuration = (
                feature_configuration._cc_feature_configuration_no_parse_headers()
            )
        else:
            cc_feature_configuration = get_cc_feature_configuration(
                feature_configuration = feature_configuration,
            )

        strict_includes = []
        for swift_info in swift_infos:
            for module in swift_info.direct_modules:
                if not module.clang:
                    continue
                if module.clang.strict_includes:
                    strict_includes.append(module.clang.strict_includes)

        # We pass these to `cc_common.compile` as flags instead of using the
        # `quote_includes` argument because we do not want them to be propagated
        # to dependencies via the compilation context that `cc_common.compile`
        # returns.
        strict_include_flags = [
            "-iquote{}".format(path)
            for path in depset(transitive = strict_includes).to_list()
        ]

        compilation_context, compilation_outputs = cc_common.compile(
            actions = actions,
            cc_toolchain = toolchains.cc,
            compilation_contexts = compilation_contexts,
            defines = defines,
            feature_configuration = cc_feature_configuration,
            language = language,
            name = target_name,
            private_hdrs = private_hdrs,
            public_hdrs = public_hdrs,
            srcs = srcs,
            user_compile_flags = copts + strict_include_flags,
            variables_extension = variables_extension,
        )
        return compilation_context, compilation_outputs

    # If there were no C/Objective-C sources or headers, create the compilation
    # context manually. This avoids having Bazel create an action that results
    # in an empty module map that won't contribute meaningfully to layering
    # checks anyway.
    if defines:
        direct_compilation_contexts = [
            cc_common.create_compilation_context(defines = depset(defines)),
        ]
    else:
        direct_compilation_contexts = []

    return (
        merge_compilation_contexts(
            direct_compilation_contexts = direct_compilation_contexts,
            transitive_compilation_contexts = compilation_contexts,
        ),
        cc_common.create_compilation_outputs(),
    )

def _cross_imported_swift_infos(*, swift_toolchain, user_swift_infos):
    """Returns `SwiftInfo` providers for any cross-imported modules.

    Args:
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        user_swift_infos: A list of `SwiftInfo` providers from regular and
            private dependencies of the target being compiled. The direct
            modules of these providers will be used to determine which
            cross-import modules need to be implicitly added to the target's
            compilation prerequisites, if any.

    Returns:
        A list of `SwiftInfo` providers representing cross-import overlays
        needed for compilation.
    """

    # Build a "set" containing the module names of direct dependencies so that
    # we can do quicker hash-based lookups below.
    direct_module_names = {}
    for swift_info in user_swift_infos:
        for module_context in swift_info.direct_modules:
            direct_module_names[module_context.name] = True

    # For each cross-import overlay registered with the toolchain, add its
    # `SwiftInfo` providers to the list if both its declaring and bystanding
    # modules were imported.
    overlay_swift_infos = []
    for overlay in swift_toolchain.cross_import_overlays:
        if (overlay.declaring_module in direct_module_names and
            overlay.bystanding_module in direct_module_names):
            overlay_swift_infos.extend(overlay.swift_infos)

    return overlay_swift_infos

def _construct_compile_plan(
        *,
        actions,
        extract_const_values,
        feature_configuration,
        generated_header_name,
        hdrs,
        module_name,
        srcs,
        target_name,
        user_compile_flags):
    """Declares output files and optional output file map for a compile action.

    Args:
        actions: The object used to register actions.
        extract_const_values: A Boolean value indicating whether constant values
            should be extracted during this compilation.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        generated_header_name: The desired name of the generated header for this
            module, or `None` if no header should be generated.
        hdrs: A list of C/Objective-C header files that should be propagated by
            the module being compiled, if this is a mixed language target.
        module_name: The name of the Swift module being compiled.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.
        user_compile_flags: The flags that will be passed to the compile action,
            which are scanned to determine whether a single frontend invocation
            will be used or not.

    Returns:
        A `struct` that should be merged into the `prerequisites` of the
        compilation action.
    """

    swift_srcs = []
    c_srcs = []
    c_private_hdrs = []
    for f in srcs:
        if f.extension == "swift":
            swift_srcs.append(f)
        elif f.extension in C_HEADER_EXTENSIONS:
            c_private_hdrs.append(f)
        else:
            c_srcs.append(f)

    if not swift_srcs:
        fail("A Swift module must have at least one Swift source file.")

    # First, declare "constant" outputs (outputs whose nature doesn't change
    # depending on compilation mode, like WMO vs. non-WMO).
    swiftmodule_file = actions.declare_file(
        "{}.swiftmodule".format(module_name),
    )
    swiftdoc_file = actions.declare_file("{}.swiftdoc".format(module_name))

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_DECLARE_SWIFTSOURCEINFO,
    ):
        swiftsourceinfo_file = actions.declare_file(
            "{}.swiftsourceinfo".format(module_name),
        )
    else:
        swiftsourceinfo_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_SWIFTINTERFACE,
    ):
        swiftinterface_file = actions.declare_file(
            "{}.swiftinterface".format(module_name),
        )
    else:
        swiftinterface_file = None

    # If requested, generate the Swift header for this library so that it can be
    # included by Objective-C code that depends on it.
    if generated_header_name:
        generated_header = _declare_validated_generated_header(
            actions = actions,
            generated_header_name = generated_header_name,
        )
    else:
        generated_header = None

    # Now, declare outputs like object files for which there may be one or many,
    # depending on the compilation mode.
    output_nature = _emitted_output_nature(
        feature_configuration = feature_configuration,
        user_compile_flags = user_compile_flags,
    )

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
    ):
        indexstore_directory = actions.declare_directory(
            "{}.indexstore".format(target_name),
        )
        include_index_unit_paths = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_MODULAR_INDEXING,
        )
    else:
        indexstore_directory = None
        include_index_unit_paths = False

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just
        # declare the output file that the compiler will generate and there are
        # no other partial outputs.
        object_files = [actions.declare_file("{}.o".format(target_name))]
        const_values_files = [
            actions.declare_file("{}.swiftconstvalues".format(target_name)),
        ]
        output_file_map = None
        codegen_outputs = [struct(
            objects = object_files,
            other_outputs = const_values_files,
        )]
        # TODO(b/147451378): Support indexing even with a single object file.

    else:
        # Otherwise, we need to create an output map that lists the individual
        # object files so that we can pass them all to the archive action.
        output_info = _declare_multiple_outputs_and_write_output_file_map(
            actions = actions,
            extract_const_values = extract_const_values,
            is_wmo = output_nature.is_wmo,
            srcs = swift_srcs,
            target_name = target_name,
            include_index_unit_paths = include_index_unit_paths,
        )
        object_files = output_info.object_files
        const_values_files = output_info.const_values_files
        output_file_map = output_info.output_file_map
        codegen_outputs = output_info.codegen_outputs

    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OPT,
    ):
        macro_expansion_directory = actions.declare_directory(
            "{}.macro-expansions".format(target_name),
        )
    else:
        macro_expansion_directory = None

    compile_outputs = struct(
        const_values_files = const_values_files,
        generated_header_file = generated_header,
        indexstore_directory = indexstore_directory,
        macro_expansion_directory = macro_expansion_directory,
        object_files = object_files,
        output_file_map = output_file_map,
        swiftdoc_file = swiftdoc_file,
        swiftinterface_file = swiftinterface_file,
        swiftmodule_file = swiftmodule_file,
        swiftsourceinfo_file = swiftsourceinfo_file,
    )
    return struct(
        codegen_outputs = codegen_outputs,
        c_inputs = struct(
            private_hdrs = c_private_hdrs,
            public_hdrs = hdrs,
            srcs = c_srcs,
        ),
        module_outputs = struct(
            generated_header_file = generated_header,
            # TODO: b/351801556 - Verify that this is correct; it may need to be
            # done by the codegen actions.
            macro_expansion_directory = macro_expansion_directory,
            swiftdoc_file = swiftdoc_file,
            swiftinterface_file = swiftinterface_file,
            swiftmodule_file = swiftmodule_file,
            swiftsourceinfo_file = swiftsourceinfo_file,
        ),
        output_file_map = output_file_map,
        output_nature = output_nature,
        # TODO: b/351801556 - Migrate all the action configuration logic off
        # this legacy structure.
        outputs = compile_outputs,
        swift_inputs = struct(
            srcs = swift_srcs,
        ),
    )

def _declare_per_source_output_file(actions, extension, target_name, src):
    """Declares a file for a per-source output file during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled), when it is expected
    that certain outputs (such as object files) produce one output per source
    file rather than one for the entire module.

    Args:
        actions: The context's actions object.
        extension: The output file's extension, without a leading dot.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File`.
    """
    objs_dir = "{}_objs".format(target_name)
    owner_rel_path = owner_relative_path(src).replace(" ", "__SPACE__")
    basename = paths.basename(owner_rel_path)
    dirname = paths.join(objs_dir, paths.dirname(owner_rel_path))

    return actions.declare_file(
        paths.join(dirname, "{}.{}".format(basename, extension)),
    )

def _declare_multiple_outputs_and_write_output_file_map(
        actions,
        extract_const_values,
        is_wmo,
        srcs,
        target_name,
        include_index_unit_paths):
    """Declares low-level outputs and writes the output map for a compilation.

    Args:
        actions: The object used to register actions.
        extract_const_values: A Boolean value indicating whether constant values
            should be extracted during this compilation.
        is_wmo: A Boolean value indicating whether whole-module-optimization was
            requested.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.
        include_index_unit_paths: Whether to include "index-unit-output-path" paths in the output
            file map.

    Returns:
        A `struct` with the following fields:

        *   `object_files`: A list of object files that were declared and
            recorded in the output file map, which should be tracked as outputs
            of the compilation action.
        *   `output_file_map`: A `File` that represents the output file map that
            was written and that should be passed as an input to the compilation
            action via the `-output-file-map` flag.
    """
    output_map_file = actions.declare_file(
        "{}.output_file_map.json".format(target_name),
    )

    # Collect the outputs that are expected to be produced by codegen actions.
    # In a WMO build, all object files (and related codegen outputs, like
    # const-values files) are emitted by a single frontend action, *regardless*
    # of whether the compilation is multi-threaded (i.e., produces multiple
    # outputs) or not. In a non-WMO build, there will be one frontend action
    # per source file.
    codegen_outputs = []

    # The output map data, which is keyed by source path and will be written to
    # `output_map_file`.
    output_map = {}
    whole_module_map = {}

    # Output files that will be emitted by the compiler.
    output_objs = []
    const_values_files = []

    for src in srcs:
        # Declare the object file (there is one per source file).
        obj = _declare_per_source_output_file(
            actions = actions,
            extension = "o",
            target_name = target_name,
            src = src,
        )
        output_objs.append(obj)
        file_outputs = {
            "object": obj.path,
        }
        if include_index_unit_paths:
            file_outputs["index-unit-output-path"] = obj.path

        if not is_wmo:
            const_values_file = None
            if extract_const_values:
                const_values_file = _declare_per_source_output_file(
                    actions = actions,
                    extension = "swiftconstvalues",
                    target_name = target_name,
                    src = src,
                )
                const_values_files.append(const_values_file)
                file_outputs["const-values"] = const_values_file.path

            codegen_outputs.append(struct(
                objects = [obj],
                other_outputs = compact([const_values_file]),
            ))

        output_map[src.path] = file_outputs

    if is_wmo:
        if extract_const_values:
            const_value_file = actions.declare_file(
                "{}.swiftconstvalues".format(target_name),
            )
            const_values_files.append(const_value_file)
            whole_module_map["const-values"] = const_value_file.path

        codegen_outputs.append(struct(
            objects = output_objs,
            other_outputs = const_values_files,
        ))

    if whole_module_map:
        output_map[""] = whole_module_map

    actions.write(
        content = json.encode(output_map),
        output = output_map_file,
    )

    return struct(
        codegen_outputs = codegen_outputs,
        const_values_files = const_values_files,
        object_files = output_objs,
        output_file_map = output_map_file,
    )

def _declare_validated_generated_header(actions, generated_header_name):
    """Validates and declares the explicitly named generated header.

    If the file does not have a `.h` extension or conatins path separators, the
    build will fail.

    Args:
        actions: The context's `actions` object.
        generated_header_name: The desired name of the generated header.

    Returns:
        A `File` that should be used as the output for the generated header.
    """
    if "/" in generated_header_name:
        fail(
            "The generated header for a Swift module may not contain " +
            "directory components (got '{}').".format(generated_header_name),
        )

    extension = paths.split_extension(generated_header_name)[1]
    if extension != ".h":
        fail(
            "The generated header for a Swift module must have a '.h' " +
            "extension (got '{}').".format(generated_header_name),
        )

    return actions.declare_file(generated_header_name)

def _emitted_output_nature(feature_configuration, user_compile_flags):
    """Returns information about the nature of emitted compilation outputs.

    The compiler emits a single object if it is invoked with whole-module
    optimization enabled and is single-threaded (`-num-threads` is not present
    or is equal to 1); otherwise, it emits one object file per source file.

    Args:
        feature_configuration: The feature configuration for the current
            compilation.
        user_compile_flags: The options passed into the compile action.

    Returns:
        A struct containing the following fields:

        *   `emits_multiple_objects`: `True` if the Swift frontend emits an
            object file per source file, instead of a single object file for the
            whole module, in a compilation action with the given flags.
        *   `is_wmo`: `True` if whole-module-optimization was requested.
    """
    is_wmo = (
        is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE__WMO_IN_SWIFTCOPTS,
        ) or
        are_all_features_enabled(
            feature_configuration = feature_configuration,
            feature_names = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ) or
        is_wmo_manually_requested(user_compile_flags)
    )

    # We check the feature first because that implies that `-num-threads 1` was
    # present in `--swiftcopt`, which overrides all other flags (like the user
    # compile flags, which come from the target's `copts`). Only fallback to
    # checking the flags if the feature is disabled.
    is_single_threaded = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS,
    ) or find_num_threads_flag_value(user_compile_flags) == 1

    return struct(
        emits_multiple_objects = not (is_wmo and is_single_threaded),
        is_wmo = is_wmo,
    )

def _write_deps_modules_file(
        actions,
        deps_modules_file,
        direct_module_names):
    """Writes a file containing the module names of direct dependencies.

    This file is used by the Swift worker process to perform layering checks;
    its contents are compared against the modules actually imported by the Swift
    code.

    Args:
        actions: The object used to register actions.
        deps_modules_file: The output file that will contain the list of
            imported module names.
        direct_module_names: The list of names of modules that are the direct
            dependencies of the code being compiled.
    """
    deps_mapping = actions.args()
    deps_mapping.set_param_file_format("multiline")
    deps_mapping.add_all(direct_module_names)

    actions.write(
        content = deps_mapping,
        output = deps_modules_file,
    )

def _maybe_create_const_protocols_file(actions, swift_infos, target_name):
    """Create the const extraction protocols file, if necessary.

    Args:
        actions: The object used to register actions.
        swift_infos: A list of `SwiftInfo` providers describing the dependencies
            of the code being compiled.
        target_name: The name of the build target, which is used to generate
            output file names.

    Returns:
        A file passed as an input to the compiler that lists the protocols whose
        conforming types should have values extracted.
    """
    const_gather_protocols = []
    for swift_info in swift_infos:
        for module_context in swift_info.direct_modules:
            const_gather_protocols.extend(
                module_context.const_gather_protocols,
            )

    # If there are no protocols to extract, return early.
    if not const_gather_protocols:
        return None

    # Create the input file to the compiler, which contains a JSON array of
    # protocol names.
    const_gather_protocols_file = actions.declare_file(
        "{}_const_extract_protocols.json".format(target_name),
    )
    actions.write(
        content = json.encode(const_gather_protocols),
        output = const_gather_protocols_file,
    )
    return const_gather_protocols_file
