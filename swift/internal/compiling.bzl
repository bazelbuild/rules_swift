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
load("@bazel_skylib//lib:sets.bzl", "sets")
load(
    ":action_names.bzl",
    "SWIFT_ACTION_COMPILE",
    "SWIFT_ACTION_COMPILE_MODULE_INTERFACE",
    "SWIFT_ACTION_PRECOMPILE_C_MODULE",
)
load(":actions.bzl", "is_action_enabled", "run_toolchain_action")
load(":explicit_module_map_file.bzl", "write_explicit_swift_module_map_file")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_LAYERING_CHECK_SWIFT",
    "SWIFT_FEATURE_MODULAR_INDEXING",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP",
    "SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__WMO_IN_SWIFTCOPTS",
)
load(
    ":features.bzl",
    "are_all_features_enabled",
    "get_cc_feature_configuration",
    "is_feature_enabled",
)
load(":module_maps.bzl", "write_module_map")
load(
    ":utils.bzl",
    "compact",
    "compilation_context_for_explicit_module_compilation",
    "merge_compilation_contexts",
    "owner_relative_path",
    "struct_fields",
)
load(":wmo.bzl", "find_num_threads_flag_value", "is_wmo_manually_requested")
load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftInfo",
    "create_clang_module_inputs",
    "create_swift_module_context",
    "create_swift_module_inputs",
)

def compile_module_interface(
        *,
        actions,
        compilation_contexts,
        copts = [],
        feature_configuration,
        module_name,
        swiftinterface_file,
        swift_infos,
        swift_toolchain):
    """Compiles a Swift module interface.

    Args:
        actions: The context's `actions` object.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        copts: A list of compiler flags that apply to the target being built.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `derive_swift_module_name` to generate a
            default from the target's label if needed.
        swiftinterface_file: The Swift module interface file to compile.
        swift_infos: A list of `SwiftInfo` providers from dependencies of the
            target being compiled.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.

    Returns:
        A Swift module context (as returned by `create_swift_module_context`)
        that contains the Swift (and potentially C/Objective-C) compilation
        prerequisites of the compiled module. This should typically be
        propagated by a `SwiftInfo` provider of the calling rule, and the
        `CcCompilationContext` inside the Clang module substructure should be
        propagated by the `CcInfo` provider of the calling rule.
    """
    swiftmodule_file = actions.declare_file("{}.swiftmodule".format(module_name))

    merged_compilation_context = merge_compilation_contexts(
        transitive_compilation_contexts = compilation_contexts + [
            cc_info.compilation_context
            for cc_info in swift_toolchain.implicit_deps_providers.cc_infos
        ],
    )
    merged_swift_info = SwiftInfo(
        swift_infos = (
            swift_infos + swift_toolchain.implicit_deps_providers.swift_infos
        ),
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

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        explicit_swift_module_map_file = explicit_swift_module_map_file,
        genfiles_dir = feature_configuration._genfiles_dir,
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
        feature_configuration = feature_configuration,
        outputs = [swiftmodule_file],
        prerequisites = prerequisites,
        progress_message = "Compiling Swift module {} from textual interface".format(module_name),
        swift_toolchain = swift_toolchain,
    )

    module_context = create_swift_module_context(
        name = module_name,
        clang = create_clang_module_inputs(
            compilation_context = merged_compilation_context,
            module_map = None,
        ),
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

    return module_context

def compile(
        *,
        actions,
        additional_inputs = [],
        compilation_contexts,
        copts = [],
        defines = [],
        feature_configuration,
        generated_header_name = None,
        module_name,
        private_swift_infos = [],
        srcs,
        swift_infos,
        swift_toolchain,
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
        copts: A list of compiler flags that apply to the target being built.
            These flags, along with those from Bazel's Swift configuration
            fragment (i.e., `--swiftcopt` command line flags) are scanned to
            determine whether whole module optimization is being requested,
            which affects the nature of the output files.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        generated_header_name: The name of the Objective-C generated header that
            should be generated for this module. If omitted, no header will be
            generated.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `derive_swift_module_name` to generate a
            default from the target's label if needed.
        private_swift_infos: A list of `SwiftInfo` providers from private
            (implementation-only) dependencies of the target being compiled. The
            modules defined by these providers are used as dependencies of the
            Swift module being compiled but not of the Clang module for the
            generated header.
        srcs: The Swift source files to compile.
        swift_infos: A list of `SwiftInfo` providers from non-private
            dependencies of the target being compiled. The modules defined by
            these providers are used as dependencies of both the Swift module
            being compiled and the Clang module for the generated header.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        A `struct` with the following fields:

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

            *   `indexstore_directory`: A directory-type `File` that represents
                the indexstore output files created when the feature
                `swift.index_while_building` is enabled.
    """

    # Apply the module alias for the module being compiled, if present.
    module_alias = swift_toolchain.module_aliases.get(module_name)
    if module_alias:
        original_module_name = module_name
        module_name = module_alias
    else:
        original_module_name = None

    # Collect the `SwiftInfo` providers that represent the dependencies of the
    # Objective-C generated header module -- this includes the dependencies of
    # the Swift module, plus any additional dependencies that the toolchain says
    # are required for all generated header modules. These are used immediately
    # below to write the module map for the header's module (to provide the
    # `use` declarations), and later in this function when precompiling the
    # module.
    generated_module_deps_swift_infos = (
        swift_infos +
        swift_toolchain.generated_header_module_implicit_deps_providers.swift_infos
    )

    compile_outputs = _declare_compile_outputs(
        srcs = srcs,
        actions = actions,
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        generated_module_deps_swift_infos = generated_module_deps_swift_infos,
        module_name = module_name,
        target_name = target_name,
        user_compile_flags = copts,
    )
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
    ]) + compile_outputs.object_files

    merged_compilation_context = merge_compilation_contexts(
        transitive_compilation_contexts = compilation_contexts + [
            cc_info.compilation_context
            for cc_info in swift_toolchain.implicit_deps_providers.cc_infos
        ],
    )

    all_swift_infos = (
        swift_infos +
        private_swift_infos +
        swift_toolchain.implicit_deps_providers.swift_infos +
        _cross_imported_swift_infos(
            swift_toolchain = swift_toolchain,
            user_swift_infos = swift_infos + private_swift_infos,
        )
    )
    merged_swift_info = SwiftInfo(swift_infos = all_swift_infos)

    # Flattening this `depset` is necessary because we need to extract the
    # module maps or precompiled modules out of structured values and do so
    # conditionally. This should not lead to poor performance because the
    # flattening happens only once as the action is being registered, rather
    # than the same `depset` being flattened and re-merged multiple times up
    # the build graph.
    transitive_modules = merged_swift_info.transitive_modules.to_list()

    transitive_swiftmodules = []
    defines_set = sets.make(defines)
    for module in transitive_modules:
        swift_module = module.swift
        if not swift_module:
            continue
        transitive_swiftmodules.append(swift_module.swiftmodule)
        if swift_module.defines:
            defines_set = sets.union(
                defines_set,
                sets.make(swift_module.defines),
            )

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

    prerequisites = struct(
        additional_inputs = additional_inputs,
        always_include_headers = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS,
        ),
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        defines = sets.to_list(defines_set),
        deps_modules_file = deps_modules_file,
        explicit_swift_module_map_file = explicit_swift_module_map_file,
        genfiles_dir = feature_configuration._genfiles_dir,
        is_swift = True,
        module_name = module_name,
        original_module_name = original_module_name,
        source_files = srcs,
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
        user_compile_flags = copts,
        # Merge the compile outputs into the prerequisites.
        **struct_fields(compile_outputs)
    )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_COMPILE,
        feature_configuration = feature_configuration,
        outputs = all_compile_outputs,
        prerequisites = prerequisites,
        progress_message = "Compiling Swift module {}".format(module_name),
        swift_toolchain = swift_toolchain,
    )

    # If a header and module map were generated for this Swift module, attempt
    # to precompile the explicit module for that header as well.
    if generated_header_name and not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
    ):
        compilation_context_to_compile = (
            compilation_context_for_explicit_module_compilation(
                compilation_contexts = [
                    cc_common.create_compilation_context(
                        headers = depset([
                            compile_outputs.generated_header_file,
                        ]),
                    ),
                    merged_compilation_context,
                ],
                swift_infos = swift_infos,
            )
        )

        pcm_outputs = _precompile_clang_module(
            actions = actions,
            cc_compilation_context = compilation_context_to_compile,
            feature_configuration = feature_configuration,
            is_swift_generated_header = True,
            module_map_file = compile_outputs.generated_module_map_file,
            module_name = module_name,
            swift_infos = generated_module_deps_swift_infos,
            swift_toolchain = swift_toolchain,
            target_name = target_name,
        )
        if pcm_outputs:
            precompiled_module = pcm_outputs.pcm_file
        else:
            precompiled_module = None
    else:
        precompiled_module = None

    module_context = create_swift_module_context(
        name = module_name,
        clang = create_clang_module_inputs(
            compilation_context = _create_cc_compilation_context(
                actions = actions,
                compilation_contexts = compilation_contexts,
                defines = defines,
                feature_configuration = feature_configuration,
                public_hdrs = compact([compile_outputs.generated_header_file]),
                swift_toolchain = swift_toolchain,
                target_name = target_name,
            ),
            module_map = compile_outputs.generated_module_map_file,
            precompiled_module = precompiled_module,
        ),
        is_system = False,
        swift = create_swift_module_inputs(
            defines = defines,
            original_module_name = original_module_name,
            swiftdoc = compile_outputs.swiftdoc_file,
            swiftinterface = compile_outputs.swiftinterface_file,
            swiftmodule = compile_outputs.swiftmodule_file,
            swiftsourceinfo = compile_outputs.swiftsourceinfo_file,
        ),
    )

    compilation_outputs = cc_common.create_compilation_outputs(
        objects = depset(compile_outputs.object_files),
        pic_objects = depset(compile_outputs.object_files),
    )

    return struct(
        module_context = module_context,
        compilation_outputs = compilation_outputs,
        supplemental_outputs = struct(
            indexstore_directory = compile_outputs.indexstore_directory,
        ),
    )

def precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        feature_configuration,
        module_map_file,
        module_name,
        swift_toolchain,
        target_name,
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
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.

    Returns:
        A struct containing the precompiled module and optional indexstore directory,
        or `None` if the toolchain or target does not support precompiled modules.
    """
    return _precompile_clang_module(
        actions = actions,
        cc_compilation_context = cc_compilation_context,
        feature_configuration = feature_configuration,
        is_swift_generated_header = False,
        module_map_file = module_map_file,
        module_name = module_name,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = target_name,
    )

def _precompile_clang_module(
        *,
        actions,
        cc_compilation_context,
        feature_configuration,
        is_swift_generated_header,
        module_map_file,
        module_name,
        swift_infos = [],
        swift_toolchain,
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
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        is_swift_generated_header: If True, the action is compiling the
            Objective-C header generated by the Swift compiler for a module.
        module_map_file: A textual module map file that defines the Clang module
            to be compiled.
        module_name: The name of the top-level module in the module map that
            will be compiled.
        swift_infos: A list of `SwiftInfo` providers representing dependencies
            required to compile this module.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        A struct containing the precompiled module and optional indexstore directory,
        or `None` if the toolchain or target does not support precompiled modules.
    """

    # Exit early if the toolchain does not support precompiled modules or if the
    # feature configuration for the target being built does not want a module to
    # be emitted.
    if not is_action_enabled(
        action_name = SWIFT_ACTION_PRECOMPILE_C_MODULE,
        swift_toolchain = swift_toolchain,
    ):
        return None
    if not is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_C_MODULE,
    ):
        return None

    precompiled_module = actions.declare_file(
        "{}.swift.pcm".format(target_name),
    )

    if not is_swift_generated_header:
        implicit_swift_infos = (
            swift_toolchain.clang_implicit_deps_providers.swift_infos
        )
        cc_compilation_context = merge_compilation_contexts(
            direct_compilation_contexts = [cc_compilation_context],
            transitive_compilation_contexts = [
                cc_info.compilation_context
                for cc_info in swift_toolchain.clang_implicit_deps_providers.cc_infos
            ],
        )
    else:
        implicit_swift_infos = []

    if not is_swift_generated_header and implicit_swift_infos:
        swift_infos = list(swift_infos)
        swift_infos.extend(implicit_swift_infos)

    if swift_infos:
        merged_swift_info = SwiftInfo(swift_infos = swift_infos)
        transitive_modules = merged_swift_info.transitive_modules.to_list()
    else:
        transitive_modules = []

    outputs = [precompiled_module]
    if are_all_features_enabled(
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
        cc_compilation_context = cc_compilation_context,
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
        feature_configuration = feature_configuration,
        outputs = outputs,
        prerequisites = prerequisites,
        progress_message = "Precompiling C module {}".format(module_name),
        swift_toolchain = swift_toolchain,
    )

    return struct(
        indexstore_directory = indexstore_directory,
        pcm_file = precompiled_module,
    )

def _create_cc_compilation_context(
        *,
        actions,
        compilation_contexts,
        defines,
        feature_configuration,
        public_hdrs,
        swift_toolchain,
        target_name):
    """Creates a `CcCompilationContext` to propagate for a Swift module.

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
        defines: Symbols that should be defined by passing `-D` to the compiler.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        public_hdrs: Public headers that should be propagated by the new
            compilation context (for example, the module's generated header).
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        The `CcCompilationContext` that should be propagated by the calling
        target.
    """

    # If we are propagating headers, call `cc_common.compile` to get the
    # compilation context instead of creating it directly. This gives the
    # C++/Objective-C logic in Bazel an opportunity to register its own actions
    # relevant to the headers, like creating a layering check module map.
    # Without this, Swift targets won't be treated as `use`d modules when
    # generating the layering check module map for an `objc_library`, and those
    # layering checks will fail when the Objective-C code tries to import the
    # `swift_library`'s headers.
    if public_hdrs:
        compilation_context, _ = cc_common.compile(
            actions = actions,
            cc_toolchain = swift_toolchain.cc_toolchain_info,
            compilation_contexts = compilation_contexts,
            defines = defines,
            feature_configuration = get_cc_feature_configuration(
                feature_configuration = feature_configuration,
            ),
            name = target_name,
            public_hdrs = public_hdrs,
        )
        return compilation_context

    # If there were no headers, create the compilation context manually. This
    # avoids having Bazel create an action that results in an empty module map
    # that won't contribute meaningfully to layering checks anyway.
    if defines:
        direct_compilation_contexts = [
            cc_common.create_compilation_context(defines = depset(defines)),
        ]
    else:
        direct_compilation_contexts = []

    return merge_compilation_contexts(
        direct_compilation_contexts = direct_compilation_contexts,
        transitive_compilation_contexts = compilation_contexts,
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

def _declare_compile_outputs(
        *,
        actions,
        feature_configuration,
        generated_header_name,
        generated_module_deps_swift_infos,
        module_name,
        srcs,
        target_name,
        user_compile_flags):
    """Declares output files and optional output file map for a compile action.

    Args:
        actions: The object used to register actions.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        generated_header_name: The desired name of the generated header for this
            module, or `None` if no header should be generated.
        generated_module_deps_swift_infos: `SwiftInfo` providers from
            dependencies of the module for the generated header of the target
            being compiled.
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

    # First, declare "constant" outputs (outputs whose nature doesn't change
    # depending on compilation mode, like WMO vs. non-WMO).
    swiftmodule_file = actions.declare_file(
        "{}.swiftmodule".format(module_name),
    )
    swiftdoc_file = actions.declare_file("{}.swiftdoc".format(module_name))
    swiftsourceinfo_file = actions.declare_file(
        "{}.swiftsourceinfo".format(module_name),
    )

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
        # Collect the names of Clang modules that the module being built
        # directly depends on.
        dependent_module_names = sets.make()
        for swift_info in generated_module_deps_swift_infos:
            for module in swift_info.direct_modules:
                if module.clang:
                    sets.insert(dependent_module_names, module.name)

        generated_module_map = actions.declare_file(
            "{}.swift.modulemap".format(target_name),
        )
        write_module_map(
            actions = actions,
            dependent_module_names = sorted(
                sets.to_list(dependent_module_names),
            ),
            module_map_file = generated_module_map,
            module_name = module_name,
            public_headers = [generated_header],
        )
    else:
        generated_module_map = None

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
        output_file_map = None
        # TODO(b/147451378): Support indexing even with a single object file.

    else:
        # Otherwise, we need to create an output map that lists the individual
        # object files so that we can pass them all to the archive action.
        output_info = _declare_multiple_outputs_and_write_output_file_map(
            actions = actions,
            srcs = srcs,
            target_name = target_name,
            include_index_unit_paths = include_index_unit_paths,
        )
        object_files = output_info.object_files
        output_file_map = output_info.output_file_map

    return struct(
        generated_header_file = generated_header,
        generated_module_map_file = generated_module_map,
        indexstore_directory = indexstore_directory,
        object_files = object_files,
        output_file_map = output_file_map,
        swiftdoc_file = swiftdoc_file,
        swiftinterface_file = swiftinterface_file,
        swiftmodule_file = swiftmodule_file,
        swiftsourceinfo_file = swiftsourceinfo_file,
    )

def _declare_per_source_object_file(actions, target_name, src):
    """Declares a file for a per-source object file during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled); in that case, there
    is a `.o` file produced for each source file, rather than a single `.o` for
    the entire module.

    Args:
        actions: The context's actions object.
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
        paths.join(dirname, "{}.o".format(basename)),
    )

def _declare_multiple_outputs_and_write_output_file_map(
        actions,
        srcs,
        target_name,
        include_index_unit_paths):
    """Declares low-level outputs and writes the output map for a compilation.

    Args:
        actions: The object used to register actions.
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

    # The output map data, which is keyed by source path and will be written to
    # `output_map_file`.
    output_map = {}

    # Object files that will be used to build the archive.
    output_objs = []

    for src in srcs:
        # Declare the object file (there is one per source file).
        obj = _declare_per_source_object_file(
            actions = actions,
            target_name = target_name,
            src = src,
        )
        output_objs.append(obj)
        file_outputs = {
            "object": obj.path,
        }
        if include_index_unit_paths:
            file_outputs["index-unit-output-path"] = obj.path
        output_map[src.path] = file_outputs

    actions.write(
        content = json.encode(output_map),
        output = output_map_file,
    )

    return struct(
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

def swift_library_output_map(name):
    """Returns the dictionary of implicit outputs for a `swift_library`.

    This function is used to specify the `outputs` of the `swift_library` rule;
    as such, its arguments must be named exactly the same as the attributes to
    which they refer.

    Args:
        name: The name of the target being built.

    Returns:
        The implicit outputs dictionary for a `swift_library`.
    """
    return {
        "archive": "lib{}.a".format(name),
    }

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

    return struct(emits_multiple_objects = not (is_wmo and is_single_threaded))

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
