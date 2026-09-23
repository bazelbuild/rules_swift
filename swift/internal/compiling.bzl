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

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load(
    "//swift:providers.bzl",
    "SwiftInfo",
    "create_clang_module_inputs",
    "create_swift_module_context",
    "create_swift_module_inputs",
)
load(
    ":action_names.bzl",
    "SWIFT_ACTION_COMPILE",
    "SWIFT_ACTION_COMPILE_MODULE_INTERFACE",
    "SWIFT_ACTION_DERIVE_FILES",
    "SWIFT_ACTION_DUMP_AST",
    "SWIFT_ACTION_PRECOMPILE_C_MODULE",
)
load(":actions.bzl", "is_action_enabled", "run_toolchain_action")
load(":attrs.bzl", "C_HEADER_EXTENSIONS")
load(":explicit_module_map_file.bzl", "write_explicit_swift_module_map_file")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_ADD_DEFAULT_PRECOMPILED_MODULES",
    "SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT",
    "SWIFT_FEATURE_DECLARE_SWIFTSOURCEINFO",
    "SWIFT_FEATURE_EMIT_BC",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_LOCALIZED_STRINGS",
    "SWIFT_FEATURE_EMIT_PRIVATE_SWIFTINTERFACE",
    "SWIFT_FEATURE_EMIT_SWIFTDOC",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_EMBEDDED",
    "SWIFT_FEATURE_FULL_LTO",
    "SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_LAYERING_CHECK_EXTERNAL_SWIFT",
    "SWIFT_FEATURE_LAYERING_CHECK_FOR_C_DEPS",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
    "SWIFT_FEATURE_LAYERING_CHECK_UNUSED_DEPS",
    "SWIFT_FEATURE_LOAD_PLUGINS_FROM_DIRECT_DEPENDENCIES",
    "SWIFT_FEATURE_MODULAR_INDEXING",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_PROPAGATE_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_THIN_LTO",
    "SWIFT_FEATURE_USE_C_MODULES",
    "SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP",
    "SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__WMO_IN_SWIFTCOPTS",
)
load(
    ":features.bzl",
    "are_all_features_enabled",
    "gather_toolchains",
    "get_cc_feature_configuration",
    "is_feature_enabled",
    "upcoming_and_experimental_features",
    "warnings_as_errors_from_features",
)
load(":module_maps.bzl", "write_module_map")
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
load(":wmo.bzl", "find_num_threads_flag_value", "is_wmo_manually_requested")

def transitive_swift_dependency_inputs(
        transitive_modules,
        include_module_metadata = False):
    """Returns Swift dependency artifacts that must be present in the sandbox.

    Args:
        transitive_modules: A list of transitive Swift module contexts.
        include_module_metadata: Whether to include available `.swiftdoc` and
            `.swiftsourceinfo` files for dependencies with a Swift module.

    Returns:
        A list of `.swiftmodule` files and the preferred textual interface file
        for each Swift dependency, plus module metadata files if requested.
    """
    inputs = []

    for module in transitive_modules:
        swift_module = module.swift
        if not swift_module:
            continue

        if type(swift_module.swiftmodule) == "File":
            inputs.append(swift_module.swiftmodule)

        if include_module_metadata and swift_module.swiftmodule:
            inputs.extend(compact([
                swift_module.swiftdoc,
                swift_module.swiftsourceinfo,
            ]))

        interface_file = (
            swift_module.private_swiftinterface or
            swift_module.swiftinterface
        )
        if interface_file:
            inputs.append(interface_file)

    return inputs

def _explicit_swift_module_map_info(
        *,
        actions,
        feature_configuration,
        target_name,
        transitive_modules):
    """Returns the explicit Swift module map file and matching Swift inputs."""
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP,
    ):
        module_contexts = transitive_modules
        filename = "{}.swift-explicit-module-map.json".format(target_name)
    elif is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_C_MODULES,
    ):
        # Keep non-system Swift deps on search paths, but include system
        # modules to make sure everything loads them with the same behavior
        module_contexts = [
            module
            for module in transitive_modules
            if module.is_system
        ]
        if not module_contexts:
            return struct(file = None, inputs = [])

        filename = "{}.swift-system-explicit-module-map.json".format(target_name)
    else:
        return struct(file = None, inputs = [])

    explicit_swift_module_map_file = actions.declare_file(filename)
    write_explicit_swift_module_map_file(
        actions = actions,
        explicit_swift_module_map_file = explicit_swift_module_map_file,
        module_contexts = module_contexts,
    )
    return struct(
        file = explicit_swift_module_map_file,
        inputs = transitive_swift_dependency_inputs(
            module_contexts,
            include_module_metadata = True,
        ),
    )

def create_compilation_context(defines, srcs, transitive_modules):
    """Cretes a compilation context for a Swift target.

    Args:
        defines: A list of defines
        srcs: A list of Swift source files used to compile the target.
        transitive_modules: A list of modules (as returned by
            `create_swift_module_context`) from the transitive dependencies of
            the target.

    Returns:
        A `struct` containing four fields:

        *   `defines`: A sequence of defines used when compiling the target.
            Includes the defines for the target and its transitive dependencies.
        *   `direct_sources`: A sequence of Swift source files used to compile
            the target.
        *   `module_maps`: A sequence of module maps used to compile the clang
            module for this target.
        *   `swiftmodules`: A sequence of swiftmodules depended on by the
            target.
    """
    defines_set = sets.make(defines)
    module_maps = []
    swiftmodules = []
    for module in transitive_modules:
        if (module.clang and module.clang.module_map and
            (module.clang.precompiled_module or not module.is_system)):
            module_maps.append(module.clang.module_map)

        swift_module = module.swift
        if not swift_module:
            continue
        swiftmodules.append(swift_module.swiftmodule)
        if swift_module.defines:
            defines_set = sets.union(
                defines_set,
                sets.make(swift_module.defines),
            )

    # Tuples are used instead of lists since they need to be frozen
    return struct(
        defines = tuple(sets.to_list(defines_set)),
        direct_sources = tuple(srcs),
        module_maps = tuple(module_maps),
        swiftmodules = tuple(swiftmodules),
    )

def compile_module_interface(
        *,
        actions,
        additional_inputs = [],
        clang_module = None,
        compilation_contexts,
        copts = [],
        exec_group = None,
        feature_configuration,
        is_framework = False,
        module_name,
        swiftinterface_file,
        swift_infos,
        swift_toolchain = None,
        target_name,
        toolchains = None,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE):
    """Compiles a Swift module interface.

    Args:
        actions: The context's `actions` object.
        additional_inputs: A list of `File`s that should be available to the
            compile action in the sandbox but are not referenced on the command
            line. The typical use case is making a sibling `.private.swiftinterface`
            available alongside the public `.swiftinterface` so the compiler can
            resolve SPI references during the textual-interface build.
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
            `configure_features`.
        is_framework: True if this module is a Framework module, false othwerise.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `derive_swift_module_name` to generate a
            default from the target's label if needed.
        swiftinterface_file: The Swift module interface file to compile.
        swift_infos: A list of `SwiftInfo` providers from dependencies of the
            target being compiled.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the interface is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: The toolchain type of the `swift_toolchain` which is
            used for the proper selection of the execution platform inside
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
    toolchains = gather_toolchains(
        swift_toolchain = swift_toolchain,
        toolchains = toolchains,
    )

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
    transitive_swift_dependency_inputs_list = transitive_swift_dependency_inputs(
        transitive_modules,
    )

    if clang_module:
        transitive_modules.append(create_swift_module_context(
            name = module_name,
            clang = clang_module,
            label = feature_configuration._label,
        ))

    explicit_swift_module_map_info = _explicit_swift_module_map_info(
        actions = actions,
        feature_configuration = feature_configuration,
        target_name = target_name,
        transitive_modules = transitive_modules,
    )

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
        additional_inputs = additional_inputs,
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        explicit_swift_module_map_file = explicit_swift_module_map_info.file,
        explicit_swift_module_map_inputs = explicit_swift_module_map_info.inputs,
        genfiles_dir = feature_configuration._genfiles_dir,
        indexstore_directory = indexstore_directory,
        is_swift = True,
        module_name = module_name,
        objc_include_paths_workaround = depset(),
        source_files = [swiftinterface_file],
        swiftmodule_file = swiftmodule_file,
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        transitive_swift_dependency_inputs = transitive_swift_dependency_inputs_list,
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
        label = feature_configuration._label,
        swift = create_swift_module_inputs(
            indexstore = indexstore_directory,
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
        cc_infos,
        copts = [],
        c_copts = [],
        defines = [],
        local_defines = [],
        exec_group = None,
        extra_swift_infos = [],
        feature_configuration,
        generated_header_name = None,
        hdrs = [],
        is_test = None,
        include_dev_srch_paths = None,
        module_name,
        package_name,
        plugins = [],
        private_cc_infos = [],
        private_swift_infos = [],
        srcs,
        swift_infos,
        swift_toolchain = None,
        target_name,
        toolchains = None,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
        workspace_name):
    """Compiles a Swift module.

    Args:
        actions: The context's `actions` object.
        additional_inputs: A list of `File`s representing additional input files
            that need to be passed to the Swift compile action because they are
            referenced by compiler flags.
        cc_infos: A list of `CcInfo` providers that represent C/Objective-C
            requirements of the target being compiled, such as Swift-compatible
            preprocessor defines, header search paths, and so forth. These are
            typically retrieved from a target's dependencies.
        copts: A list of compiler flags that apply to the Swift sources in the
            target being built.
            These flags, along with those from the `@rules_swift//swift:copt`
            build setting (typically passed as `--swiftcopt`) are scanned to
            determine whether whole module optimization is being requested,
            which affects the nature of the output files.
        c_copts: A list of compiler flags that apply to the C/Objective-C
            sources in the target being built.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        local_defines: Symbols defined for this target's Swift and C/Objective-C
            compilations only, without propagation to dependents.
        exec_group: Runs the Swift compilation action under the given execution
            group's context. If `None`, the default execution group is used.
        extra_swift_infos: Extra `SwiftInfo` providers that aren't contained
            by the `deps` of the target being compiled but are required for
            compilation.
        feature_configuration: A feature configuration obtained from
            `configure_features`.
        is_test: Deprecated. This argument will be removed in the next major
            release. Use the `include_dev_srch_paths` attribute instead.
            Represents if the `testonly` value of the context.
        include_dev_srch_paths: A `bool` that indicates whether the developer
            framework search paths will be added to the compilation command.
        generated_header_name: The name of the Objective-C generated header that
            should be generated for this module. If omitted, no header will be
            generated.
        hdrs: Public C/Objective-C headers to export from a mixed-language
            module. Private headers should be provided via `srcs`.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `derive_swift_module_name` to generate a
            default from the target's label if needed.
        package_name: The semantic package of the name of the Swift module
            being compiled.
        plugins: A list of `SwiftCompilerPluginInfo` providers that represent
            plugins that should be loaded by the compiler.
        private_cc_infos: A list of `CcInfos`s that represent private
            (non-propagated) C/Objective-C requirements of the target being
            compiled, such as Swift-compatible preprocessor defines, header
            search paths, and so forth. These are typically retrieved from a
            target's `private_deps`.
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
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        toolchain_type: A toolchain type of the `swift_toolchain` which is used
            for the proper selection of the execution platform inside
            `run_toolchain_action`.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: The toolchain type of the `swift_toolchain` which is
            used for the proper selection of the execution platform inside
            `run_toolchain_action`.
        workspace_name: The name of the workspace for which the code is being
             compiled, which is used to determine unique file paths for some
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

            *   `ast_files`: A list of `File`s output from the `DUMP_AST`
                action.

            *   `const_values_files`: A list of `File`s that contains JSON
                representations of constant values extracted from the source
                files, if requested via a direct dependency.

            *   `indexstore_directory`: A directory-type `File` that represents
                the indexstore output files created when the feature
                `swift.index_while_building` is enabled.

            *   `localized_strings_directory`: A directory-type `File` that
                represents the location where the Swift compiler's
                `.stringsdata` localized-string files were written (one per
                source file), created when the feature
                `swift.emit_localized_strings` is enabled.

            *   `macro_expansion_directory`: A directory-type `File` that
                represents the location where macro expansion files were written
                (only in debug/fastbuild and only when the toolchain supports
                macros).
    """
    toolchains = gather_toolchains(
        swift_toolchain = swift_toolchain,
        toolchains = toolchains,
    )

    swift_srcs = []
    c_srcs = []
    c_private_hdrs = []
    for src in srcs:
        if src.extension == "swift":
            swift_srcs.append(src)
        elif src.extension in C_HEADER_EXTENSIONS:
            c_private_hdrs.append(src)
        else:
            c_srcs.append(src)

    if not swift_srcs:
        fail("A Swift module must have at least one Swift source file.")

    # Apply the module alias for the module being compiled, if present.
    module_alias = toolchains.swift.module_aliases.get(module_name)
    if module_alias:
        original_module_name = module_name
        module_name = module_alias
    else:
        original_module_name = None

    implicit_swift_infos, implicit_cc_infos = get_swift_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = toolchains.swift,
    )

    # Collect the `SwiftInfo` providers that represent the dependencies of the
    # Objective-C generated header module -- this includes the dependencies of
    # the Swift module, plus any additional dependencies that the toolchain says
    # are required for all generated header modules. These are used immediately
    # below to write the module map for the header's module (to provide the
    # `use` declarations), and later in this function when precompiling the
    # module.
    generated_module_deps_swift_infos = (
        swift_infos + implicit_swift_infos +
        toolchains.swift.generated_header_module_implicit_deps_providers.swift_infos
    )

    # These are the `SwiftInfo` providers that will be merged with the compiled
    # module context and returned as the `swift_info` field of this function's
    # result. Note that private deps are explicitly not included here, as they
    # are not supposed to be propagated.
    #
    # TODO(allevato): It would potentially clean things up if we included the
    # toolchain's implicit dependencies here as well. Do this and make sure it
    # doesn't break anything unexpected.
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_C_MODULES,
    ):
        cross_imported_overlays = _cross_imported_overlays(
            swift_toolchain = toolchains.swift,
            user_swift_infos = swift_infos + private_swift_infos + implicit_swift_infos,
        )
    else:
        cross_imported_overlays = []
    swift_infos_to_propagate = swift_infos + [
        swift_info
        for overlay in cross_imported_overlays
        for swift_info in overlay.swift_infos
    ]
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
    for info in extra_swift_infos:
        transitive_modules.extend(info.transitive_modules.to_list())

    const_gather_protocols_file = toolchains.swift.const_protocols_to_gather

    compile_outputs = _declare_compile_outputs(
        srcs = swift_srcs,
        actions = actions,
        extract_const_values = bool(const_gather_protocols_file),
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        module_name = module_name,
        target_name = target_name,
        user_compile_flags = copts,
    )

    split_derived_file_generation = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION,
    )

    if split_derived_file_generation:
        all_compile_outputs = compact([
            compile_outputs.indexstore_directory,
            compile_outputs.localized_strings_directory,
        ]) + compile_outputs.object_files + compile_outputs.const_values_files
        all_derived_outputs = compact([
            # The `.swiftmodule` file is explicitly listed as the first output
            # because it will always exist and because Bazel uses it as a key for
            # various things (such as the filename prefix for param files generated
            # for that action). This guarantees some predictability.
            compile_outputs.swiftmodule_file,
            compile_outputs.generated_header_file,
            compile_outputs.macro_expansion_directory,
            compile_outputs.swiftdoc_file,
            compile_outputs.swiftinterface_file,
            compile_outputs.private_swiftinterface_file,
            compile_outputs.swiftsourceinfo_file,
        ])
    else:
        all_compile_outputs = compact([
            # The `.swiftmodule` file is explicitly listed as the first output
            # because it will always exist and because Bazel uses it as a key for
            # various things (such as the filename prefix for param files generated
            # for that action). This guarantees some predictability.
            compile_outputs.swiftmodule_file,
            compile_outputs.swiftdoc_file,
            compile_outputs.swiftinterface_file,
            compile_outputs.private_swiftinterface_file,
            compile_outputs.swiftsourceinfo_file,
            compile_outputs.generated_header_file,
            compile_outputs.indexstore_directory,
            compile_outputs.localized_strings_directory,
            compile_outputs.macro_expansion_directory,
        ]) + compile_outputs.object_files + compile_outputs.const_values_files
        all_derived_outputs = []

    # Unlike upstream, the Swift compilation needs the merged linking context
    # to disable autolinking of static prebuilt frameworks. Retain the CcInfos
    # for that purpose, but propagate only the public compilation contexts.
    compilation_contexts = [
        cc_info.compilation_context
        for cc_info in cc_infos
    ]
    merged_cc_info = cc_common.merge_cc_infos(
        cc_infos = cc_infos + private_cc_infos +
                   implicit_cc_infos,
    )

    defines_set = sets.make(defines)
    for module in transitive_modules:
        swift_module = module.swift
        if not swift_module:
            continue
        if swift_module.defines:
            defines_set = sets.union(
                defines_set,
                sets.make(swift_module.defines),
            )
    transitive_swift_dependency_inputs_list = transitive_swift_dependency_inputs(
        transitive_modules,
    )

    explicit_swift_module_map_info = _explicit_swift_module_map_info(
        actions = actions,
        feature_configuration = feature_configuration,
        target_name = target_name,
        transitive_modules = transitive_modules,
    )

    swift_layering_check_enabled = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_LAYERING_CHECK_SWIFT,
    )

    if swift_layering_check_enabled and feature_configuration._label.repo_name:
        swift_layering_check_enabled = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_LAYERING_CHECK_EXTERNAL_SWIFT,
        )

    if swift_layering_check_enabled:
        # For performance, don't worry about uniquing the module names; since
        # Bazel doesn't allow repeated `deps` the only time a duplicate might
        # appear is if someone explicitly depends on an implicit dependency that
        # came from the toolchain. This is relatively unlikely, and the worker
        # will dedupe it anyway.
        direct_module_names = []
        for dep_swift_info in all_swift_infos:
            for dep_module_context in dep_swift_info.direct_modules:
                direct_module_names.append(dep_module_context.name)

        # Excludes implicitly added deps
        unused_check_module_name_groups = []
        if is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_LAYERING_CHECK_UNUSED_DEPS,
        ):
            for dep_swift_info in swift_infos + private_swift_infos:
                direct_module_names_for_dep = [
                    dep_module_context.name
                    for dep_module_context in dep_swift_info.direct_modules
                ]
                if direct_module_names_for_dep:
                    unused_check_module_name_groups.append(
                        ",".join(direct_module_names_for_dep),
                    )

        validate_system_modules = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_USE_C_MODULES,
        ) and not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_ADD_DEFAULT_PRECOMPILED_MODULES,
        )

        layering_check_transitive_modules = [
            module_context
            for module_context in transitive_modules
            # If we want to validate system modules that happens below
            if not module_context.is_system
        ]
        if validate_system_modules:
            # Default precompiled modules are disabled, so SDK modules are no
            # longer implicit imports and should participate in layering checks.
            for swift_info in toolchains.swift.system_modules.swift_infos:
                layering_check_transitive_modules.extend(
                    swift_info.transitive_modules.to_list(),
                )

        deps_modules_file = actions.declare_file(
            "{}.deps-module-mapping".format(target_name),
        )
        _write_deps_modules_file(
            actions = actions,
            deps_modules_file = deps_modules_file,
            direct_module_names = direct_module_names,
            transitive_modules = layering_check_transitive_modules,
            unused_check_module_name_groups = unused_check_module_name_groups,
        )
    else:
        deps_modules_file = None

    used_plugins = list(plugins)
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_LOAD_PLUGINS_FROM_DIRECT_DEPENDENCIES,
    ):
        plugin_module_contexts = []
        for swift_info in swift_infos + private_swift_infos:
            plugin_module_contexts.extend(swift_info.direct_modules)
    else:
        plugin_module_contexts = transitive_modules

    for module_context in plugin_module_contexts:
        if module_context.swift and module_context.swift.plugins:
            used_plugins.extend(module_context.swift.plugins)

    if include_dev_srch_paths != None and is_test != None:
        fail("""\
Both `include_dev_srch_paths` and `is_test` cannot be specified. Please select \
one, preferring `include_dev_srch_paths`.\
""")
    include_dev_srch_paths_value = False
    if include_dev_srch_paths != None:
        include_dev_srch_paths_value = include_dev_srch_paths
    elif is_test != None:
        print("""\
WARNING: swift_common.compile(is_test = ...) is deprecated. Update your rules \
to use swift_common.compile(include_dev_srch_paths = ...) instead.\
""")  # buildifier: disable=print
        include_dev_srch_paths_value = is_test

    upcoming_features, experimental_features = upcoming_and_experimental_features(
        feature_configuration = feature_configuration,
    )

    werror_warning_groups = warnings_as_errors_from_features(
        feature_configuration = feature_configuration,
    )

    # Compile the original C headers before Swift. The Swift compilation imports
    # this incomplete module; only the complete module, including the generated
    # header, is propagated to dependents.
    incomplete_compilation_context, _ = _compile_c_inputs(
        actions = actions,
        additional_inputs = additional_inputs,
        compilation_contexts = compilation_contexts,
        copts = c_copts,
        defines = defines,
        local_defines = local_defines,
        feature_configuration = feature_configuration,
        includes = [],
        private_hdrs = c_private_hdrs,
        private_swift_infos = private_swift_infos,
        public_hdrs = hdrs,
        srcs = [],
        swift_infos = swift_infos_to_propagate,
        target_name = "{}.incomplete".format(target_name),
        toolchains = toolchains,
    )
    incomplete_header_module = _compile_clang_module_for_swift_module(
        actions = actions,
        compilation_context = incomplete_compilation_context,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        is_incomplete_header_module = bool(generated_header_name),
        is_swift_generated_header = False,
        module_name = module_name,
        should_index = not generated_header_name,
        swift_infos = swift_infos,
        target_name = target_name,
        toolchains = toolchains,
        toolchain_type = toolchain_type,
    )
    merged_compilation_context = merge_compilation_contexts(
        direct_compilation_contexts = [incomplete_compilation_context],
        transitive_compilation_contexts = [
            cc_info.compilation_context
            for cc_info in private_cc_infos + implicit_cc_infos
        ],
    )
    prerequisites = struct(
        additional_inputs = additional_inputs + toolchains.cc.all_files.to_list(),
        always_include_headers = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS,
        ),
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        const_gather_protocols_file = const_gather_protocols_file,
        cc_linking_context = merged_cc_info.linking_context,
        cross_import_overlays = cross_imported_overlays,
        defines = sets.to_list(defines_set),
        deps_modules_file = deps_modules_file,
        developer_dirs = toolchains.swift.developer_dirs,
        experimental_features = experimental_features,
        explicit_swift_module_map_file = explicit_swift_module_map_info.file,
        explicit_swift_module_map_inputs = explicit_swift_module_map_info.inputs,
        genfiles_dir = feature_configuration._genfiles_dir,
        include_dev_srch_paths = include_dev_srch_paths_value,
        is_swift = True,
        local_defines = local_defines,
        mixed_module_clang_inputs = incomplete_header_module,
        module_name = module_name,
        original_module_name = original_module_name,
        package_name = package_name,
        plugins = collections.uniq(used_plugins),
        source_files = swift_srcs,
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        transitive_swift_dependency_inputs = transitive_swift_dependency_inputs_list,
        upcoming_features = upcoming_features,
        user_compile_flags = copts,
        werror_warning_groups = werror_warning_groups,
        workspace_name = workspace_name,
        # Merge the compile outputs into the prerequisites.
        **struct_fields(compile_outputs)
    )

    if split_derived_file_generation:
        run_toolchain_action(
            actions = actions,
            action_name = SWIFT_ACTION_DERIVE_FILES,
            exec_group = exec_group,
            feature_configuration = feature_configuration,
            outputs = all_derived_outputs,
            prerequisites = prerequisites,
            progress_message = "Generating derived files for Swift module %{label}",
            swift_toolchain = toolchains.swift,
            toolchain_type = toolchain_type,
        )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_COMPILE,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = all_compile_outputs,
        prerequisites = prerequisites,
        progress_message = "Compiling Swift module %{label}",
        swift_toolchain = toolchains.swift,
        toolchain_type = toolchain_type,
    )

    # Dump AST has to run in its own action because `-dump-ast` is incompatible
    # with emitting dependency files, which compile/derive files use when
    # compiling via the worker.
    # Given usage of AST files is expected to be limited compared to other
    # compile outputs, moving generation off of the critical path is likely
    # a reasonable tradeoff for the additional action.
    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_DUMP_AST,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = compile_outputs.ast_files,
        prerequisites = prerequisites,
        progress_message = "Dumping Swift AST for %{label}",
        swift_toolchain = toolchains.swift,
        toolchain_type = toolchain_type,
    )

    compilation_context = create_compilation_context(
        defines = defines,
        srcs = swift_srcs,
        transitive_modules = transitive_modules,
    )

    if compile_outputs.generated_header_file:
        public_hdrs = hdrs + [compile_outputs.generated_header_file]
    else:
        public_hdrs = hdrs

    if compile_outputs.generated_module_map_file and is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_PROPAGATE_GENERATED_MODULE_MAP,
    ):
        public_hdrs.append(compile_outputs.generated_module_map_file)
        includes = [compile_outputs.generated_module_map_file.dirname]
    else:
        includes = []

    c_compilation_context, c_compilation_outputs = _compile_c_inputs(
        actions = actions,
        additional_inputs = additional_inputs,
        compilation_contexts = compilation_contexts,
        copts = c_copts,
        defines = defines,
        local_defines = local_defines,
        feature_configuration = feature_configuration,
        has_generated_header = bool(compile_outputs.generated_header_file),
        includes = includes,
        private_hdrs = c_private_hdrs,
        private_swift_infos = private_swift_infos,
        public_hdrs = public_hdrs,
        srcs = c_srcs,
        swift_infos = swift_infos_to_propagate,
        target_name = target_name,
        toolchains = toolchains,
    )

    if generated_header_name:
        generated_header_module = _compile_clang_module_for_swift_module(
            actions = actions,
            compilation_context = c_compilation_context,
            exec_group = exec_group,
            feature_configuration = feature_configuration,
            is_incomplete_header_module = False,
            is_swift_generated_header = True,
            module_map_file = compile_outputs.generated_module_map_file,
            module_name = module_name,
            should_index = True,
            swift_infos = generated_module_deps_swift_infos,
            target_name = target_name,
            toolchains = toolchains,
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
        compilation_context = compilation_context,
        is_system = False,
        label = feature_configuration._label,
        swift = create_swift_module_inputs(
            ast_files = compile_outputs.ast_files,
            defines = defines,
            generated_header = compile_outputs.generated_header_file,
            indexstore = compile_outputs.indexstore_directory,
            original_module_name = original_module_name,
            plugins = plugins,
            private_swiftinterface = compile_outputs.private_swiftinterface_file,
            swiftdoc = compile_outputs.swiftdoc_file,
            swiftinterface = compile_outputs.swiftinterface_file,
            swiftmodule = compile_outputs.swiftmodule_file,
            swiftsourceinfo = compile_outputs.swiftsourceinfo_file,
            const_protocols_to_gather = compile_outputs.const_values_files,
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
            ast_files = compile_outputs.ast_files,
            const_values_files = compile_outputs.const_values_files,
            indexstore_directory = compile_outputs.indexstore_directory,
            localized_strings_directory = compile_outputs.localized_strings_directory,
            macro_expansion_directory = compile_outputs.macro_expansion_directory,
        ),
        swift_info = SwiftInfo(
            modules = [module_context],
            swift_infos = swift_infos_to_propagate,
        ),
    )

def _compile_clang_module_for_swift_module(
        *,
        actions,
        compilation_context,
        exec_group,
        feature_configuration,
        is_incomplete_header_module,
        is_swift_generated_header,
        module_map_file = None,
        module_name,
        should_index,
        swift_infos,
        target_name,
        toolchains,
        toolchain_type):
    """Builds the initial or complete Clang half of a mixed Swift module.

    The initial module excludes the generated header. A VFS overlay makes its
    module map and PCM appear at the complete module's paths, so Swift doesn't
    serialize two conflicting definitions for LLDB. The special overlay basename
    matches the Swift frontend's handling of Xcode's unextended header module.

    Returns a struct containing the compilation context, module name, module
    map, optional PCM and VFS overlay, and optional virtual map/PCM paths.
    """
    has_headers = (
        compilation_context.direct_public_headers or
        compilation_context.direct_private_headers
    )
    if not has_headers or (is_swift_generated_header and is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
    )):
        return struct(
            compilation_context = None,
            module_name = None,
            module_map_file = None,
            precompiled_module = None,
            vfs_overlay_file = None,
            virtual_module_map_path = None,
            virtual_precompiled_module_path = None,
        )

    dependent_module_names = sets.make()
    for swift_info in swift_infos:
        for module in swift_info.direct_modules:
            if module.clang:
                sets.insert(dependent_module_names, module.name)

    if not module_map_file:
        module_map_file = actions.declare_file(
            "{}_modulemap/_/module{}.modulemap".format(
                target_name,
                ".incomplete" if is_incomplete_header_module else "",
            ),
        )
    write_module_map(
        actions = actions,
        dependent_module_names = sorted(sets.to_list(dependent_module_names)),
        module_map_file = module_map_file,
        module_name = module_name,
        private_headers = compilation_context.direct_private_headers,
        public_headers = [
            header
            for header in compilation_context.direct_public_headers
            if header != module_map_file
        ],
        workspace_relative = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
        ),
    )

    compile_result = _precompile_clang_module(
        actions = actions,
        cc_compilation_context = compilation_context,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        file_extension = "incomplete.pcm" if is_incomplete_header_module else "pcm",
        is_swift_generated_header = is_swift_generated_header,
        module_map_file = module_map_file,
        module_name = module_name,
        should_index = should_index,
        swift_infos = swift_infos,
        target_name = target_name,
        toolchains = toolchains,
        toolchain_type = toolchain_type,
        user_compile_flags = [],
    )
    precompiled_module = compile_result.clang_module.precompiled_module if compile_result else None

    vfs_overlay_file = None
    virtual_module_map_path = None
    virtual_precompiled_module_path = None
    if is_incomplete_header_module:
        virtual_module_map_path = paths.join(module_map_file.dirname, "module.modulemap")
        roots = [{
            "type": "directory",
            "name": module_map_file.dirname,
            "contents": [{
                "type": "file",
                "name": "module.modulemap",
                "external-contents": module_map_file.path,
            }],
        }]
        if precompiled_module:
            virtual_pcm_basename = "{}.swift.pcm".format(target_name)
            virtual_precompiled_module_path = paths.join(
                precompiled_module.dirname,
                virtual_pcm_basename,
            )
            roots.append({
                "type": "directory",
                "name": precompiled_module.dirname,
                "contents": [{
                    "type": "file",
                    "name": virtual_pcm_basename,
                    "external-contents": precompiled_module.path,
                }],
            })
        vfs_overlay_file = actions.declare_file(
            "{}_objs/unextended-module-overlay.yaml".format(target_name),
        )
        actions.write(
            output = vfs_overlay_file,
            content = json.encode({
                "version": 0,
                "case-sensitive": True,
                "roots": roots,
            }),
        )

    return struct(
        compilation_context = compilation_context,
        module_name = module_name,
        module_map_file = module_map_file,
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
        swift_toolchain = None,
        target_name,
        toolchains = None,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
        swift_infos = [],
        unchecked_include_headers = None,
        user_compile_flags = []):
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
            `configure_features`.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchain_type: The toolchain type of the Swift toolchain.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.
        unchecked_include_headers: A `depset` of `File`s that can be reached by
            `#include`s in the files of this module that Clang does not
            layering-check, such as all of the module's transitive headers if
            its module map declares excluded headers. If this is not `None` and
            `swift.layering_check_for_c_deps` is enabled, only the headers that
            Clang can read while compiling the module are provided as inputs:
            the headers of the module and of its direct dependencies, the
            headers in this `depset`, and the headers of dependencies that don't
            have a precompiled module or that can be reached by includes that
            Clang does not check. If `None` (the default), all of the headers in
            `cc_compilation_context` are provided as inputs, and the returned
            `clang_module` treats all of them as reachable by such includes.
        user_compile_flags: Additional Clang flags to pass to the precompile
            action. Each flag is forwarded to the underlying clang invocation
            via `-Xcc`.

    Returns:
        A struct containing the following fields:

        *   `clang_module`: A structure (as returned by
            `create_clang_module_inputs`) containing the headers, module map,
            and precompiled module. This can be used if you need to construct a
            `SwiftInfo` provider for a pure C module (that is, if you are doing
            something that `swift_clang_module_aspect` cannot handle on its own)
            or it can be passing into `swift_common.compile_module_interface`
            when compiling a textual interface that has an underlying C module.
        *   `indexstore_directory`: The indexstore directory for the precompiled
            module, if any.
    """
    return _precompile_clang_module(
        actions = actions,
        cc_compilation_context = cc_compilation_context,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        is_swift_generated_header = False,
        module_map_file = module_map_file,
        module_name = module_name,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = target_name,
        toolchains = toolchains,
        toolchain_type = toolchain_type,
        unchecked_include_headers = unchecked_include_headers,
        user_compile_flags = user_compile_flags,
    )

def _precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        exec_group = None,
        feature_configuration,
        file_extension = "pcm",
        is_swift_generated_header,
        module_map_file,
        module_name,
        should_index = True,
        swift_infos = [],
        swift_toolchain = None,
        target_name,
        toolchains = None,
        toolchain_type,
        unchecked_include_headers = None,
        user_compile_flags):
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
            `configure_features`.
        file_extension: The extension of the precompiled module output, used to
            distinguish incomplete mixed-language modules from complete ones.
        is_swift_generated_header: If True, the action is compiling the
            Objective-C header generated by the Swift compiler for a module.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        should_index: Whether to produce an indexstore when indexing is enabled.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.
        toolchain_type: The toolchain type of the Swift toolchain.
        unchecked_include_headers: See `precompile_clang_module`.
        user_compile_flags: Additional Clang flags to pass to the precompile
            action. Each flag is forwarded to the underlying clang invocation
            via `-Xcc`.

    Returns:
        A struct containing the following fields:

        *   `clang_module`: A structure (as returned by
            `create_clang_module_inputs`) containing the headers, module map,
            and precompiled module. This can be used if you need to construct a
            `SwiftInfo` provider for a pure C module (that is, if you are doing
            something that `swift_clang_module_aspect` cannot handle on its own)
            or it can be passing into `swift_common.compile_module_interface`
            when compiling a textual interface that has an underlying C module.
        *   `indexstore_directory`: The indexstore directory for the precompiled
            module, if any.
    """
    toolchains = gather_toolchains(
        swift_toolchain = swift_toolchain,
        toolchains = toolchains,
    )

    # Exit early if the toolchain does not support precompiled modules or if the
    # feature configuration for the target being built does not want a module to
    # be emitted.
    if not is_action_enabled(
        action_name = SWIFT_ACTION_PRECOMPILE_C_MODULE,
        swift_toolchain = toolchains.swift,
    ):
        return None
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_C_MODULE,
    ):
        return None

    precompiled_module = actions.declare_file(
        "{}.swift.{}".format(target_name, file_extension),
    )

    additional_swift_infos = []
    additional_compilation_contexts = []
    if not is_swift_generated_header:
        implicit_swift_infos, implicit_cc_infos = get_clang_implicit_deps(
            feature_configuration = feature_configuration,
            swift_toolchain = toolchains.swift,
        )
        additional_swift_infos.extend(implicit_swift_infos)
        additional_compilation_contexts.extend([
            cc_info.compilation_context
            for cc_info in implicit_cc_infos
        ])

    if additional_compilation_contexts:
        cc_compilation_context = merge_compilation_contexts(
            direct_compilation_contexts = [cc_compilation_context],
            transitive_compilation_contexts = additional_compilation_contexts,
        )

    if additional_swift_infos:
        swift_infos = list(swift_infos)
        swift_infos.extend(additional_swift_infos)

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

    compilation_context_for_compilation = compilation_context_for_explicit_module_compilation(
        compilation_contexts = [cc_compilation_context],
        swift_infos = swift_infos,
    )

    # With `-fmodules-strict-decluse`, the files of the module being compiled
    # can only include the headers of that module and of the modules that it
    # depends on directly. Clang needs those headers to be present so that it
    # can map them to their modules, but the headers that they include are
    # embedded in the dependencies' precompiled modules, so the remaining
    # transitive headers don't need to be inputs of the action. The exceptions
    # are the headers that can be reached by includes that Clang doesn't check,
    # which are the includes in files that don't belong to the module being
    # compiled:
    #
    # *   The textual headers of direct dependencies can be included, and the
    #     includes in them can reach any of those dependencies' transitive
    #     headers.
    # *   Excluded headers of this module or of any of its dependencies can be
    #     included. Those are covered by `unchecked_include_headers` and by the
    #     `unchecked_include_headers` of each dependency's `clang_module`.
    #
    # The headers of the toolchain's implicit dependencies are also kept.
    if (
        unchecked_include_headers != None and
        not is_swift_generated_header and
        is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_LAYERING_CHECK_FOR_C_DEPS,
        ) and
        not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_SYSTEM_MODULE,
        ) and
        not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS,
        )
    ):
        transitive_headers_to_stage = [unchecked_include_headers]
        for swift_info in swift_infos:
            for module in swift_info.direct_modules:
                clang = module.clang
                if (
                    clang and
                    clang.module_map and
                    clang.compilation_context and
                    clang.compilation_context.direct_textual_headers
                ):
                    transitive_headers_to_stage.append(depset(
                        clang.compilation_context.direct_textual_headers,
                        transitive = [clang.compilation_context.headers],
                    ))
        for compilation_context in additional_compilation_contexts:
            transitive_headers_to_stage.append(compilation_context.headers)
        unchecked_include_headers_to_stage = depset(
            transitive = transitive_headers_to_stage,
        )
    else:
        # Provide all of the transitive headers as inputs.
        unchecked_include_headers_to_stage = None

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = compilation_context_for_compilation,
        genfiles_dir = feature_configuration._genfiles_dir,
        include_dev_srch_paths = False,
        indexstore_directory = indexstore_directory,
        index_unit_output_path = index_unit_output_path,
        is_swift = False,
        is_swift_generated_header = is_swift_generated_header,
        module_name = module_name,
        package_name = None,
        pcm_file = precompiled_module,
        source_files = [module_map_file],
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        unchecked_include_headers = unchecked_include_headers_to_stage,
        user_compile_flags = user_compile_flags,
    )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_PRECOMPILE_C_MODULE,
        exec_group = exec_group,
        feature_configuration = feature_configuration,
        outputs = outputs,
        prerequisites = prerequisites,
        progress_message = "Precompiling C module %{label}",
        swift_toolchain = toolchains.swift,
        toolchain_type = toolchain_type,
    )

    if unchecked_include_headers == None:
        # We don't know what the module map declares, so assume that modules
        # that depend on this one can reach all of its headers by includes
        # that Clang doesn't check.
        unchecked_include_headers = depset(
            compilation_context_for_compilation.direct_textual_headers,
            transitive = [compilation_context_for_compilation.headers],
        )

    return struct(
        clang_module = create_clang_module_inputs(
            compilation_context = compilation_context_for_compilation,
            module_map = module_map_file,
            precompiled_module = precompiled_module,
            unchecked_include_headers = unchecked_include_headers,
        ),
        indexstore_directory = indexstore_directory,
    )

def _compile_c_inputs(
        *,
        actions,
        additional_inputs,
        compilation_contexts,
        copts,
        defines,
        local_defines,
        feature_configuration,
        includes,
        has_generated_header = False,
        private_hdrs,
        private_swift_infos = [],
        public_hdrs,
        srcs,
        swift_infos,
        target_name,
        toolchains = None):
    """Compiles the C/Objective-C inputs for a Swift module, if any.

    The returned compilation context contains the generated Objective-C header
    for the module (if any), along with any preprocessor defines based on
    compilation settings passed to the Swift compilation.

    Args:
        actions: The context's `actions` object.
        additional_inputs: Files referenced by the C compiler options.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        copts: A list of flags that will be passed to the C/Objective-C
            compiler.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        local_defines: Symbols defined for this compilation only, without
            propagation to dependents.
        feature_configuration: A feature configuration obtained from
            `configure_features`.
        includes: Include paths that should be propagated by the new compilation
            context.
        has_generated_header: If True, the `public_hdrs` include a generated
            Objective-C header.
        private_hdrs: Private headers that should be used when compiling the
            C/Objective-C sources.
        private_swift_infos: The `SwiftInfo` providers of private dependencies,
            used only for strict include flags, not propagated module maps.
        public_hdrs: Public headers that should be propagated by the new
            compilation context (for example, the module's generated header).
        srcs: C/Objective-C source files that should be compiled, if this is a
            mixed-language module.
        swift_infos: The `SwiftInfo` providers of public dependencies. Their
            direct Clang module maps must remain discoverable when an
            Objective-C consumer imports the generated header.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        toolchains: The struct containing the Swift and C++ toolchain providers,
            as returned by `swift_common.find_all_toolchains()`.

    Returns:
        A tuple containing the `CcCompilationContext` to propagate and the
        `CcCompilationOutputs` to merge with the Swift object files.
    """

    # Generated headers can import Clang modules whose maps are carried only by
    # SwiftInfo. Add maps from public direct dependencies as transitive
    # compilation inputs.
    module_maps = depset([
        module.clang.module_map
        for swift_info in swift_infos
        for module in swift_info.direct_modules
        if module.clang and type(module.clang.module_map) == "File"
    ]).to_list()
    if module_maps:
        compilation_contexts = compilation_contexts + [
            cc_common.create_compilation_context(
                headers = depset(module_maps),
                includes = depset([module_map.dirname for module_map in module_maps]),
            ),
        ]

    # If we have C/Objective-C inputs, call `cc_common.compile` to get the
    # compilation context even if they are only headers. This gives the
    # C++/Objective-C logic in Bazel an opportunity to register its own actions
    # relevant to the headers, like creating a layering check module map.
    # Without this, Swift targets won't be treated as `use`d modules when
    # generating the layering check module map for an `objc_library`, and those
    # layering checks will fail when the Objective-C code tries to import the
    # `swift_library`'s headers.
    if private_hdrs or public_hdrs or srcs:
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

        language = toolchains.swift.cc_language
        variables_extension = {}
        if language == "objc":
            variables_extension["objc_arc"] = ""

        strict_includes = [
            module.clang.strict_includes
            for swift_info in swift_infos + private_swift_infos
            for module in swift_info.direct_modules
            if module.clang and module.clang.strict_includes
        ]

        # Keep strict include paths local to this compilation, not in CcInfo.
        strict_include_flags = [
            "-iquote{}".format(path)
            for path in depset(transitive = strict_includes).to_list()
        ]

        compilation_context, compilation_outputs = cc_common.compile(
            actions = actions,
            additional_inputs = additional_inputs,
            cc_toolchain = toolchains.cc,
            compilation_contexts = compilation_contexts,
            defines = defines,
            local_defines = local_defines,
            feature_configuration = cc_feature_configuration,
            name = target_name,
            includes = includes,
            language = language,
            private_hdrs = private_hdrs,
            public_hdrs = public_hdrs,
            srcs = srcs,
            user_compile_flags = copts + strict_include_flags,
            variables_extension = variables_extension,
        )
        return compilation_context, compilation_outputs

    # If there were no C/Objective-C inputs, create the context manually. This
    # avoids having Bazel create an action that results in an empty module map
    # that won't contribute meaningfully to layering checks anyway.
    if defines or local_defines:
        direct_compilation_contexts = [
            cc_common.create_compilation_context(
                defines = depset(defines),
                local_defines = depset(local_defines),
            ),
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

def _cross_imported_overlays(
        *,
        swift_toolchain,
        user_swift_infos):
    """Returns cross-import overlays needed for a compilation.

    Args:
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        user_swift_infos: A list of `SwiftInfo` providers from regular and
            private dependencies of the target being compiled. The direct
            modules of these providers will be used to determine which
            cross-import modules need to be implicitly added to the target's
            compilation prerequisites, if any.

    Returns:
        A list of `SwiftCrossImportOverlayInfo` providers needed for
        compilation.
    """

    # Build a "set" containing the module names of direct dependencies so that
    # we can do quicker hash-based lookups below.
    module_names = {}
    for swift_info in user_swift_infos:
        # TODO: Ideally this would only be the direct dependencies, but unless
        # you enforce layering_check it's easy to rely on this
        for module_context in swift_info.transitive_modules.to_list():
            module_names[module_context.name] = True

    # For each cross-import overlay registered with the toolchain, add its
    # `SwiftInfo` providers to the list if both its declaring and bystanding
    # modules were imported.
    overlays = []
    for overlay in swift_toolchain.cross_import_overlays:
        if (overlay.declaring_module in module_names and
            overlay.bystanding_module in module_names):
            overlays.append(overlay)

    return overlays

def _declare_compile_outputs(
        *,
        actions,
        extract_const_values,
        feature_configuration,
        generated_header_name,
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
            `configure_features`.
        generated_header_name: The desired name of the generated header for this
            module, or `None` if no header should be generated.
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

    add_target_name_to_output_path = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT,
    )

    # First, declare "constant" outputs (outputs whose nature doesn't change
    # depending on compilation mode, like WMO vs. non-WMO).
    swiftmodule_file = _declare_target_scoped_file(
        actions = actions,
        add_target_name_to_output_path = add_target_name_to_output_path,
        target_name = target_name,
        basename = "{}.swiftmodule".format(module_name),
    )

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_SWIFTDOC,
    ):
        swiftdoc_file = _declare_target_scoped_file(
            actions = actions,
            add_target_name_to_output_path = add_target_name_to_output_path,
            target_name = target_name,
            basename = "{}.swiftdoc".format(module_name),
        )
    else:
        swiftdoc_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_DECLARE_SWIFTSOURCEINFO,
    ):
        swiftsourceinfo_file = _declare_target_scoped_file(
            actions = actions,
            add_target_name_to_output_path = add_target_name_to_output_path,
            target_name = target_name,
            basename = "{}.swiftsourceinfo".format(module_name),
        )
    else:
        swiftsourceinfo_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_SWIFTINTERFACE,
    ):
        swiftinterface_file = _declare_target_scoped_file(
            actions = actions,
            add_target_name_to_output_path = add_target_name_to_output_path,
            target_name = target_name,
            basename = "{}.swiftinterface".format(module_name),
        )
    else:
        swiftinterface_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_PRIVATE_SWIFTINTERFACE,
    ):
        private_swiftinterface_file = _declare_target_scoped_file(
            actions = actions,
            add_target_name_to_output_path = add_target_name_to_output_path,
            target_name = target_name,
            basename = "{}.private.swiftinterface".format(module_name),
        )
    else:
        private_swiftinterface_file = None

    # If requested, generate the Swift header for this library so that it can be
    # included by Objective-C code that depends on it.
    if generated_header_name:
        generated_header = _declare_validated_generated_header(
            actions = actions,
            add_target_name_to_output_path = add_target_name_to_output_path,
            target_name = target_name,
            generated_header_name = generated_header_name,
        )
    else:
        generated_header = None

    # If not disabled, create a module map for the generated header file. This
    # ensures that inclusions of it are treated modularly, not textually.
    #
    # Caveat: Generated module maps are incompatible with the hack that some
    # folks are using to support mixed Objective-C and Swift modules. This
    # trap door lets them escape the module redefinition error, with the
    # caveat that certain import scenarios could lead to incorrect behavior
    # because a header can be imported textually instead of modularly.
    if generated_header and not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
    ):
        generated_module_map = actions.declare_file(
            "{}_modulemap/_/module.modulemap".format(target_name),
        )
    else:
        generated_module_map = None

    # Now, declare outputs like object files for which there may be one or many,
    # depending on the compilation mode.
    output_nature = _emitted_output_nature(
        feature_configuration = feature_configuration,
        user_compile_flags = user_compile_flags,
    )

    # Configure index-while-building if requested. IDEs and other indexing tools
    # can enable this feature on the command line during a build and then access
    # the index store artifacts that are produced.
    index_while_building = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
    )
    if (
        index_while_building and
        not _is_index_store_path_overridden(user_compile_flags)
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

    # Configure localized-string extraction if requested. The compiler emits one
    # `.stringsdata` file per source file into this directory; the file set is
    # not known at analysis time, so (like the index store) it must be a
    # declared directory output.
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_LOCALIZED_STRINGS,
    ):
        localized_strings_directory = actions.declare_directory(
            "{}.stringsdata".format(target_name),
        )
    else:
        localized_strings_directory = None

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just
        # declare the output file that the compiler will generate and there are
        # no other partial outputs.
        object_files = [actions.declare_file("{}.o".format(target_name))]
        ast_files = [
            _declare_per_source_output_file(
                actions = actions,
                extension = "ast",
                target_name = target_name,
                src = srcs[0],
            ),
        ]
        const_values_files = [
            actions.declare_file("{}.swiftconstvalues".format(target_name)),
        ]
        output_file_map = None
        derived_files_output_file_map = None
        # TODO(b/147451378): Support indexing even with a single object file.

    else:
        split_derived_file_generation = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION,
        )

        # If enabled the compiler will emit LLVM BC files instead of Mach-O object
        # files.
        # LTO implies emitting LLVM BC files, too

        full_lto_enabled = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_FULL_LTO,
        )

        thin_lto_enabled = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_THIN_LTO,
        )

        emits_bc = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_EMIT_BC,
        ) or full_lto_enabled or thin_lto_enabled

        # Otherwise, we need to create an output map that lists the individual
        # object files so that we can pass them all to the archive action.
        output_info = _declare_multiple_outputs_and_write_output_file_map(
            actions = actions,
            extract_const_values = extract_const_values,
            is_wmo = output_nature.is_wmo,
            emits_bc = emits_bc,
            split_derived_file_generation = split_derived_file_generation,
            srcs = srcs,
            target_name = target_name,
            include_index_unit_paths = include_index_unit_paths,
        )
        object_files = output_info.object_files
        ast_files = output_info.ast_files
        const_values_files = output_info.const_values_files
        output_file_map = output_info.output_file_map
        derived_files_output_file_map = output_info.derived_files_output_file_map

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
        ast_files = ast_files,
        const_values_files = const_values_files,
        generated_header_file = generated_header,
        generated_module_map_file = generated_module_map,
        indexstore_directory = indexstore_directory,
        localized_strings_directory = localized_strings_directory,
        macro_expansion_directory = macro_expansion_directory,
        private_swiftinterface_file = private_swiftinterface_file,
        object_files = object_files,
        output_file_map = output_file_map,
        derived_files_output_file_map = derived_files_output_file_map,
        swiftdoc_file = swiftdoc_file,
        swiftinterface_file = swiftinterface_file,
        swiftmodule_file = swiftmodule_file,
        swiftsourceinfo_file = swiftsourceinfo_file,
    )
    return compile_outputs

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

    # Spaces in object file paths break response-file parsing on Windows
    owner_rel_path = owner_relative_path(src).replace(" ", "_")
    basename = paths.basename(owner_rel_path)
    dirname = paths.join(objs_dir, paths.dirname(owner_rel_path))

    return actions.declare_file(
        paths.join(dirname, "{}.{}".format(basename, extension)),
    )

def _declare_multiple_outputs_and_write_output_file_map(
        actions,
        extract_const_values,
        is_wmo,
        emits_bc,
        split_derived_file_generation,
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
        emits_bc: If `True` the compiler will generate LLVM BC files instead of
            object files.
        split_derived_file_generation: Whether objects and modules are produced
            by separate actions.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.
        include_index_unit_paths: Whether to include "index-unit-output-path" paths in the output
            file map.

    Returns:
        A `struct` with the following fields:

        *   `derived_files_output_file_map`: A `File` that represents the
            output file map that should be passed to derived file generation
            actions instead of the default `output_file_map` that is used for
            producing objects only.
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

    if split_derived_file_generation:
        derived_files_output_map_file = actions.declare_file(
            "{}.derived_output_file_map.json".format(target_name),
        )
    else:
        derived_files_output_map_file = None

    # The output map data, which is keyed by source path and will be written to
    # `output_map_file`.
    output_map = {}
    derived_files_output_map = {}
    whole_module_map = {}

    # Output files that will be emitted by the compiler.
    ast_files = []
    output_objs = []
    const_values_files = []

    if extract_const_values and is_wmo:
        const_values_file = actions.declare_file(
            "{}.swiftconstvalues".format(target_name),
        )
        const_values_files.append(const_values_file)
        whole_module_map["const-values"] = const_values_file.path

    for src in srcs:
        file_outputs = {}

        ast = _declare_per_source_output_file(
            actions = actions,
            extension = "ast",
            target_name = target_name,
            src = src,
        )
        ast_files.append(ast)
        file_outputs["ast-dump"] = ast.path

        if emits_bc:
            # Declare the llvm bc file (there is one per source file).
            obj = _declare_per_source_output_file(
                actions = actions,
                extension = "bc",
                target_name = target_name,
                src = src,
            )
            output_objs.append(obj)
            file_outputs["llvm-bc"] = obj.path
        else:
            # Declare the object file (there is one per source file).
            obj = _declare_per_source_output_file(
                actions = actions,
                extension = "o",
                target_name = target_name,
                src = src,
            )
            output_objs.append(obj)
            file_outputs["object"] = obj.path

        if include_index_unit_paths:
            file_outputs["index-unit-output-path"] = obj.path

        if extract_const_values and not is_wmo:
            const_values_file = _declare_per_source_output_file(
                actions = actions,
                extension = "swiftconstvalues",
                target_name = target_name,
                src = src,
            )
            const_values_files.append(const_values_file)
            file_outputs["const-values"] = const_values_file.path

        output_map[src.path] = file_outputs

        if split_derived_file_generation and not is_wmo:
            derived_files_output_map[src.path] = {
                "swift-dependencies": paths.replace_extension(obj.path, ".swiftdeps"),
            }

    if whole_module_map:
        output_map[""] = whole_module_map

    actions.write(
        content = json.encode(struct(**output_map)),
        output = output_map_file,
    )

    if split_derived_file_generation:
        actions.write(
            content = json.encode(derived_files_output_map),
            output = derived_files_output_map_file,
        )

    return struct(
        ast_files = ast_files,
        const_values_files = const_values_files,
        derived_files_output_file_map = derived_files_output_map_file,
        object_files = output_objs,
        output_file_map = output_map_file,
    )

def _declare_target_scoped_file(
        *,
        actions,
        add_target_name_to_output_path,
        target_name,
        basename):
    if add_target_name_to_output_path:
        return actions.declare_file(paths.join(target_name, basename))
    else:
        return actions.declare_file(basename)

def _declare_validated_generated_header(
        *,
        actions,
        add_target_name_to_output_path,
        target_name,
        generated_header_name):
    """Validates and declares the explicitly named generated header.

    If the file does not have a `.h` extension, the build will fail.

    Args:
        actions: The context's `actions` object.
        add_target_name_to_output_path: Add target_name in output path. More
        info at SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT description.
        target_name: Executable target name.
        generated_header_name: The desired name of the generated header.

    Returns:
        A `File` that should be used as the output for the generated header.
    """
    extension = paths.split_extension(generated_header_name)[1]
    if extension != ".h":
        fail(
            "The generated header for a Swift module must have a '.h' " +
            "extension (got '{}').".format(generated_header_name),
        )

    return _declare_target_scoped_file(
        actions = actions,
        add_target_name_to_output_path = add_target_name_to_output_path,
        target_name = target_name,
        basename = generated_header_name,
    )

def _is_index_store_path_overridden(copts):
    """Checks if index_while_building must be disabled.

    Index while building is disabled when the copts include a custom
    `-index-store-path`.

    Args:
        copts: The list of copts to be scanned.

    Returns:
        True if the index_while_building must be disabled, otherwise False.
    """
    for opt in copts:
        if opt == "-index-store-path":
            return True
    return False

def _emitted_output_nature(feature_configuration, user_compile_flags):
    """Returns information about the nature of emitted compilation outputs.

    The compiler emits a single object if it is invoked with whole-module
    optimization enabled and is single-threaded (`-num-threads` is not present
    or is equal to 0); otherwise, it emits one object file per source file. It
    also emits a single `.swiftmodule` file for WMO builds, _regardless of
    thread count,_ so we have to treat that case separately.

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
        is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_ENABLE_EMBEDDED,
        ) or
        are_all_features_enabled(
            feature_configuration = feature_configuration,
            feature_names = [SWIFT_FEATURE_OPT, SWIFT_FEATURE_OPT_USES_WMO],
        ) or
        is_wmo_manually_requested(user_compile_flags)
    )

    # We check the feature first because that implies that `-num-threads 0` was
    # present in `--swiftcopt`, which overrides all other flags (like the user
    # compile flags, which come from the target's `copts`). Only fallback to
    # checking the flags if the feature is disabled.
    is_single_threaded = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS,
    ) or find_num_threads_flag_value(user_compile_flags) == 0

    return struct(
        emits_multiple_objects = not (is_wmo and is_single_threaded),
        is_wmo = is_wmo,
    )

def _write_deps_modules_file(
        actions,
        deps_modules_file,
        direct_module_names,
        transitive_modules,
        unused_check_module_name_groups):
    """Writes a file containing dependency module names and owning labels.

    This file is used by the Swift worker process to perform layering checks.
    Direct modules are the modules that the Swift code is allowed to import
    explicitly. Transitive modules are used to filter the imported module list
    to modules that are known to come from the Bazel dependency graph, which
    lets SDK/toolchain modules imported implicitly by the compiler be ignored.

    Args:
        actions: The object used to register actions.
        deps_modules_file: The output file that will contain the list of
            imported module names.
        direct_module_names: The list of names of modules that are the direct
            dependencies of the code being compiled.
        transitive_modules: The list of module contexts in the target's
            transitive dependency graph.
        unused_check_module_name_groups: A list of comma-separated module name
            groups. Each group represents the direct modules provided by one
            user-declared dependency and is used to detect unused dependencies.
    """
    deps_mapping = actions.args()
    deps_mapping.set_param_file_format("multiline")
    deps_mapping.add_all(direct_module_names, format_each = "direct:%s")
    for module_context in transitive_modules:
        deps_mapping.add_joined(
            [
                module_context.name,
                getattr(module_context, "label", None) or "",
            ],
            format_joined = "transitive:%s",
            join_with = "\t",
        )
    deps_mapping.add_all(unused_check_module_name_groups, format_each = "unused-check:%s")

    actions.write(
        content = deps_mapping,
        output = deps_modules_file,
    )
