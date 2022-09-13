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
load("@bazel_skylib//lib:types.bzl", "types")
load(
    ":action_names.bzl",
    "SWIFT_ACTION_COMPILE",
    "SWIFT_ACTION_COMPILE_MODULE_INTERFACE",
    "SWIFT_ACTION_DERIVE_FILES",
    "SWIFT_ACTION_DUMP_AST",
    "SWIFT_ACTION_PRECOMPILE_C_MODULE",
)
load(":actions.bzl", "is_action_enabled", "run_toolchain_action")
load(":explicit_module_map_file.bzl", "write_explicit_swift_module_map_file")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_ADD_TARGET_NAME_TO_OUTPUT",
    "SWIFT_FEATURE_EMIT_BC",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_EMIT_PRIVATE_SWIFTINTERFACE",
    "SWIFT_FEATURE_EMIT_SWIFTDOC",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_EMIT_SWIFTSOURCEINFO",
    "SWIFT_FEATURE_FULL_LTO",
    "SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_PROPAGATE_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_THIN_LTO",
    "SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP",
    "SWIFT_FEATURE_VFSOVERLAY",
    "SWIFT_FEATURE__NUM_THREADS_0_IN_SWIFTCOPTS",
    "SWIFT_FEATURE__SUPPORTS_CONST_VALUE_EXTRACTION",
    "SWIFT_FEATURE__SUPPORTS_MACROS",
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
    ":providers.bzl",
    "create_clang_module",
    "create_module",
    "create_swift_info",
    "create_swift_module",
)
load(
    ":utils.bzl",
    "compact",
    "compilation_context_for_explicit_module_compilation",
    "merge_compilation_contexts",
    "owner_relative_path",
    "struct_fields",
)
load(":vfsoverlay.bzl", "write_vfsoverlay")
load(":wmo.bzl", "find_num_threads_flag_value", "is_wmo_manually_requested")

# VFS root where all .swiftmodule files will be placed when
# SWIFT_FEATURE_VFSOVERLAY is enabled.
_SWIFTMODULES_VFS_ROOT = "/__build_bazel_rules_swift/swiftmodules"

def _module_name_safe(string):
    """Returns a transformation of `string` that is safe for module names."""
    result = ""
    saw_non_identifier_char = False
    for ch in string.elems():
        if ch.isalnum() or ch == "_":
            # If we're seeing an identifier character after a sequence of
            # non-identifier characters, append an underscore and reset our
            # tracking state before appending the identifier character.
            if saw_non_identifier_char:
                result += "_"
                saw_non_identifier_char = False
            result += ch
        elif result:
            # Only track this if `result` has content; this ensures that we
            # (intentionally) drop leading non-identifier characters instead of
            # adding a leading underscore.
            saw_non_identifier_char = True

    return result

def derive_module_name(*args):
    """Returns a derived module name from the given build label.

    For targets whose module name is not explicitly specified, the module name
    is computed using the following algorithm:

    *   The package and name components of the label are considered separately.
        All _interior_ sequences of non-identifier characters (anything other
        than `a-z`, `A-Z`, `0-9`, and `_`) are replaced by a single underscore
        (`_`). Any leading or trailing non-identifier characters are dropped.
    *   If the package component is non-empty after the above transformation,
        it is joined with the transformed name component using an underscore.
        Otherwise, the transformed name is used by itself.
    *   If this would result in a string that begins with a digit (`0-9`), an
        underscore is prepended to make it identifier-safe.

    This mapping is intended to be fairly predictable, but not reversible.

    Args:
        *args: Either a single argument of type `Label`, or two arguments of
            type `str` where the first argument is the package name and the
            second argument is the target name.

    Returns:
        The module name derived from the label.
    """
    if (len(args) == 1 and
        hasattr(args[0], "package") and
        hasattr(args[0], "name")):
        label = args[0]
        package = label.package
        name = label.name
    elif (len(args) == 2 and
          types.is_string(args[0]) and
          types.is_string(args[1])):
        package = args[0]
        name = args[1]
    else:
        fail("derive_module_name may only be called with a single argument " +
             "of type 'Label' or two arguments of type 'str'.")

    package_part = _module_name_safe(package.lstrip("//"))
    name_part = _module_name_safe(name)
    if package_part:
        module_name = package_part + "_" + name_part
    else:
        module_name = name_part
    if module_name[0].isdigit():
        module_name = "_" + module_name
    return module_name

def create_compilation_context(defines, srcs, transitive_modules):
    """Cretes a compilation context for a Swift target.

    Args:
        defines: A list of defines
        srcs: A list of Swift source files used to compile the target.
        transitive_modules: A list of modules (as returned by
            `swift_common.create_module`) from the transitive dependencies of
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
        compilation_contexts,
        feature_configuration,
        module_name,
        swiftinterface_file,
        swift_infos,
        swift_toolchain,
        target_name):
    """Compiles a Swift module interface.

    Args:
        actions: The context's `actions` object.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `swift_common.derive_module_name` to generate
            a default from the target's label if needed.
        swiftinterface_file: The Swift module interface file to compile.
        swift_infos: A list of `SwiftInfo` providers from dependencies of the
            target being compiled.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        target_name: The name of the target for which the code is being
            compiled, which is used to determine unique file paths for the
            outputs.

    Returns:
        A Swift module context (as returned by `swift_common.create_module`)
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
    merged_swift_info = create_swift_info(
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

    # We need this when generating the VFS overlay file and also when
    # configuring inputs for the compile action, so it's best to precompute it
    # here.
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_VFSOVERLAY,
    ):
        vfsoverlay_file = actions.declare_file(
            "{}.vfsoverlay.yaml".format(target_name),
        )
        write_vfsoverlay(
            actions = actions,
            swiftmodules = transitive_swiftmodules,
            vfsoverlay_file = vfsoverlay_file,
            virtual_swiftmodule_root = _SWIFTMODULES_VFS_ROOT,
        )
    else:
        vfsoverlay_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP,
    ):
        if vfsoverlay_file:
            fail("Cannot use both `swift.vfsoverlay` and `swift.use_explicit_swift_module_map` features at the same time.")

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

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        explicit_swift_module_map_file = explicit_swift_module_map_file,
        genfiles_dir = feature_configuration._genfiles_dir,
        is_swift = True,
        module_name = module_name,
        objc_include_paths_workaround = depset(),
        objc_info = None,
        source_files = [swiftinterface_file],
        swiftmodule_file = swiftmodule_file,
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
        user_compile_flags = [],
        vfsoverlay_file = vfsoverlay_file,
        vfsoverlay_search_path = _SWIFTMODULES_VFS_ROOT,
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

    module_context = create_module(
        name = module_name,
        clang = create_clang_module(
            compilation_context = merged_compilation_context,
            module_map = None,
        ),
        is_system = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_SYSTEM_MODULE,
        ),
        swift = create_swift_module(
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
        cc_infos,
        copts = [],
        defines = [],
        extra_swift_infos = [],
        feature_configuration,
        generated_header_name = None,
        is_test = None,
        include_dev_srch_paths = None,
        module_name,
        objc_infos,
        package_name,
        plugins = [],
        private_swift_infos = [],
        srcs,
        swift_infos,
        swift_toolchain,
        target_name,
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
        copts: A list of compiler flags that apply to the target being built.
            These flags, along with those from Bazel's Swift configuration
            fragment (i.e., `--swiftcopt` command line flags) are scanned to
            determine whether whole module optimization is being requested,
            which affects the nature of the output files.
        defines: Symbols that should be defined by passing `-D` to the compiler.
        extra_swift_infos: Extra `SwiftInfo` providers that aren't contained
            by the `deps` of the target being compiled but are required for
            compilation.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        is_test: Deprecated. This argument will be removed in the next major
            release. Use the `include_dev_srch_paths` attribute instead.
            Represents if the `testonly` value of the context.
        include_dev_srch_paths: A `bool` that indicates whether the developer
            framework search paths will be added to the compilation command.
        generated_header_name: The name of the Objective-C generated header that
            should be generated for this module. If omitted, no header will be
            generated.
        module_name: The name of the Swift module being compiled. This must be
            present and valid; use `swift_common.derive_module_name` to generate
            a default from the target's label if needed.
        objc_infos: A list of `apple_common.ObjC` providers that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from a target's dependencies.
        package_name: The semantic package of the name of the Swift module
            being compiled.
        plugins: A list of `SwiftCompilerPluginInfo` providers that represent
            plugins that should be loaded by the compiler.
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
        workspace_name: The name of the workspace for which the code is being
             compiled, which is used to determine unique file paths for some
             outputs.

    Returns:
        A `struct` with the following fields:

        *   `module_context`: A Swift module context (as returned by
            `swift_common.create_module`) that contains the Swift (and
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

            *   `macro_expansion_directory`: A directory-type `File` that
                represents the location where macro expansion files were written
                (only in debug/fastbuild and only when the toolchain supports
                macros).
    """

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

    # Determine if `.swiftdoc` and `.swiftsourceinfo` files should be included.
    include_swiftdoc = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_SWIFTDOC,
    )
    include_swiftsourceinfo = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_EMIT_SWIFTSOURCEINFO,
    )

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE__SUPPORTS_CONST_VALUE_EXTRACTION,
    ):
        const_protocols_to_gather_file = swift_toolchain.const_protocols_to_gather
    else:
        const_protocols_to_gather_file = []

    compile_outputs, other_outputs = _declare_compile_outputs(
        srcs = srcs,
        actions = actions,
        extract_const_values = bool(const_protocols_to_gather_file),
        feature_configuration = feature_configuration,
        generated_header_name = generated_header_name,
        generated_module_deps_swift_infos = generated_module_deps_swift_infos,
        include_swiftdoc = include_swiftdoc,
        include_swiftsourceinfo = include_swiftsourceinfo,
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
            compile_outputs.swiftinterface_file,
            compile_outputs.private_swiftinterface_file,
            compile_outputs.indexstore_directory,
            compile_outputs.macro_expansion_directory,
        ]) + compile_outputs.object_files + compile_outputs.const_values_files
        all_derived_outputs = compact([
            # The `.swiftmodule` file is explicitly listed as the first output
            # because it will always exist and because Bazel uses it as a key for
            # various things (such as the filename prefix for param files generated
            # for that action). This guarantees some predictability.
            compile_outputs.swiftmodule_file,
            compile_outputs.generated_header_file,
        ]) + other_outputs
        if include_swiftdoc:
            all_derived_outputs.append(compile_outputs.swiftdoc_file)
        if include_swiftsourceinfo:
            all_derived_outputs.append(compile_outputs.swiftsourceinfo_file)
    else:
        all_compile_outputs = compact([
            # The `.swiftmodule` file is explicitly listed as the first output
            # because it will always exist and because Bazel uses it as a key for
            # various things (such as the filename prefix for param files generated
            # for that action). This guarantees some predictability.
            compile_outputs.swiftmodule_file,
            compile_outputs.swiftinterface_file,
            compile_outputs.private_swiftinterface_file,
            compile_outputs.generated_header_file,
            compile_outputs.indexstore_directory,
            compile_outputs.macro_expansion_directory,
        ]) + compile_outputs.object_files + compile_outputs.const_values_files + other_outputs
        if include_swiftdoc:
            all_compile_outputs.append(compile_outputs.swiftdoc_file)
        if include_swiftsourceinfo:
            all_compile_outputs.append(compile_outputs.swiftsourceinfo_file)
        all_derived_outputs = []

    # In `upstream` they call `merge_compilation_contexts` on passed in
    # `compilation_contexts` instead of merging `CcInfo`s. This is because
    # they don't need the merged linking context to disable framework
    # autolinking. If we ever remove our need for `-disable-autolink-framework`,
    # we should change this to match `upstream`. Same for `apple_common.Objc`.
    compilation_contexts = [
        cc_info.compilation_context
        for cc_info in cc_infos
    ]
    merged_cc_info = cc_common.merge_cc_infos(
        cc_infos = cc_infos + swift_toolchain.implicit_deps_providers.cc_infos,
    )
    merged_objc_info = apple_common.new_objc_provider(
        providers = objc_infos + swift_toolchain.implicit_deps_providers.objc_infos,
    )

    merged_swift_info = create_swift_info(
        swift_infos = (
            swift_infos +
            private_swift_infos +
            swift_toolchain.implicit_deps_providers.swift_infos
        ),
    )

    # Flattening this `depset` is necessary because we need to extract the
    # module maps or precompiled modules out of structured values and do so
    # conditionally. This should not lead to poor performance because the
    # flattening happens only once as the action is being registered, rather
    # than the same `depset` being flattened and re-merged multiple times up
    # the build graph.
    transitive_modules = merged_swift_info.transitive_modules.to_list()
    for info in extra_swift_infos:
        transitive_modules.extend(info.transitive_modules.to_list())

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

    # We need this when generating the VFS overlay file and also when
    # configuring inputs for the compile action, so it's best to precompute it
    # here.
    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_VFSOVERLAY,
    ):
        vfsoverlay_file = actions.declare_file(
            "{}.vfsoverlay.yaml".format(target_name),
        )
        write_vfsoverlay(
            actions = actions,
            swiftmodules = transitive_swiftmodules,
            vfsoverlay_file = vfsoverlay_file,
            virtual_swiftmodule_root = _SWIFTMODULES_VFS_ROOT,
        )
    else:
        vfsoverlay_file = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP,
    ):
        if vfsoverlay_file:
            fail("Cannot use both `swift.vfsoverlay` and `swift.use_explicit_swift_module_map` features at the same time.")

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

    # As of the time of this writing (Xcode 15.0), macros are the only kind of
    # plugins that are available. Since macros do source-level transformations,
    # we only need to load plugins directly used by the module being compiled.
    # Plugins that are only used by transitive dependencies do *not* need to be
    # passed; the compiler does not attempt to load them when deserializing
    # modules.
    used_plugins = list(plugins)
    for module_context in transitive_modules:
        if module_context.swift and module_context.swift.plugins:
            used_plugins.extend(module_context.swift.plugins.to_list())

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

    prerequisites = struct(
        additional_inputs = additional_inputs,
        always_include_headers = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS,
        ),
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_cc_info.compilation_context,
        const_protocols_to_gather_file = const_protocols_to_gather_file,
        cc_linking_context = merged_cc_info.linking_context,
        defines = sets.to_list(defines_set),
        explicit_swift_module_map_file = explicit_swift_module_map_file,
        developer_dirs = swift_toolchain.developer_dirs,
        genfiles_dir = feature_configuration._genfiles_dir,
        include_dev_srch_paths = include_dev_srch_paths_value,
        is_swift = True,
        module_name = module_name,
        package_name = package_name,
        objc_info = merged_objc_info,
        plugins = depset(used_plugins),
        source_files = srcs,
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
        user_compile_flags = copts,
        vfsoverlay_file = vfsoverlay_file,
        vfsoverlay_search_path = _SWIFTMODULES_VFS_ROOT,
        workspace_name = workspace_name,
        # Merge the compile outputs into the prerequisites.
        **struct_fields(compile_outputs)
    )

    if split_derived_file_generation:
        run_toolchain_action(
            actions = actions,
            action_name = SWIFT_ACTION_DERIVE_FILES,
            feature_configuration = feature_configuration,
            outputs = all_derived_outputs,
            prerequisites = prerequisites,
            progress_message = "Generating derived files for Swift module %{label}",
            swift_toolchain = swift_toolchain,
        )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_COMPILE,
        feature_configuration = feature_configuration,
        outputs = all_compile_outputs,
        prerequisites = prerequisites,
        progress_message = "Compiling Swift module %{label}",
        swift_toolchain = swift_toolchain,
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
        feature_configuration = feature_configuration,
        outputs = compile_outputs.ast_files,
        prerequisites = prerequisites,
        progress_message = "Dumping Swift AST for %{label}",
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
                    merged_cc_info.compilation_context,
                ],
                swift_infos = swift_infos,
            )
        )
        precompiled_module = _precompile_clang_module(
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
    else:
        precompiled_module = None

    compilation_context = create_compilation_context(
        defines = defines,
        srcs = srcs,
        transitive_modules = transitive_modules,
    )

    if compile_outputs.generated_header_file:
        public_hdrs = [compile_outputs.generated_header_file]
    else:
        public_hdrs = []

    if compile_outputs.generated_module_map_file and is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_PROPAGATE_GENERATED_MODULE_MAP,
    ):
        public_hdrs.append(compile_outputs.generated_module_map_file)
        includes = [compile_outputs.generated_module_map_file.dirname]
    else:
        includes = []

    module_context = create_module(
        name = module_name,
        clang = create_clang_module(
            compilation_context = _create_cc_compilation_context(
                actions = actions,
                compilation_contexts = compilation_contexts,
                defines = defines,
                feature_configuration = feature_configuration,
                includes = includes,
                public_hdrs = public_hdrs,
                swift_toolchain = swift_toolchain,
                target_name = target_name,
            ),
            module_map = compile_outputs.generated_module_map_file,
            precompiled_module = precompiled_module,
        ),
        compilation_context = compilation_context,
        is_system = False,
        swift = create_swift_module(
            ast_files = compile_outputs.ast_files,
            defines = defines,
            indexstore = compile_outputs.indexstore_directory,
            plugins = depset(plugins),
            private_swiftinterface = compile_outputs.private_swiftinterface_file,
            swiftdoc = compile_outputs.swiftdoc_file,
            swiftinterface = compile_outputs.swiftinterface_file,
            swiftmodule = compile_outputs.swiftmodule_file,
            swiftsourceinfo = compile_outputs.swiftsourceinfo_file,
            const_protocols_to_gather = compile_outputs.const_values_files,
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
            ast_files = compile_outputs.ast_files,
            const_values_files = compile_outputs.const_values_files,
            indexstore_directory = compile_outputs.indexstore_directory,
            macro_expansion_directory = compile_outputs.macro_expansion_directory,
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
        A `File` representing the precompiled module (`.pcm`) file, or `None` if
        the toolchain or target does not support precompiled modules.
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
        A `File` representing the precompiled module (`.pcm`) file, or `None` if
        the toolchain or target does not support precompiled modules.
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
        merged_swift_info = create_swift_info(swift_infos = swift_infos)
        transitive_modules = merged_swift_info.transitive_modules.to_list()
    else:
        transitive_modules = []

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = cc_compilation_context,
        genfiles_dir = feature_configuration._genfiles_dir,
        include_dev_srch_paths = False,
        is_swift = False,
        is_swift_generated_header = is_swift_generated_header,
        module_name = module_name,
        package_name = None,
        objc_info = apple_common.new_objc_provider(),
        pcm_file = precompiled_module,
        source_files = [module_map_file],
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
    )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_PRECOMPILE_C_MODULE,
        feature_configuration = feature_configuration,
        outputs = [precompiled_module],
        prerequisites = prerequisites,
        progress_message = "Precompiling C module %{label}",
        swift_toolchain = swift_toolchain,
    )

    return precompiled_module

def _create_cc_compilation_context(
        *,
        actions,
        compilation_contexts,
        defines,
        feature_configuration,
        includes,
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
        includes: Include paths that should be propagated by the new compilation
            context.
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
            includes = includes,
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

def _declare_compile_outputs(
        *,
        actions,
        extract_const_values,
        feature_configuration,
        generated_header_name,
        generated_module_deps_swift_infos,
        include_swiftdoc,
        include_swiftsourceinfo,
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
        generated_module_deps_swift_infos: `SwiftInfo` providers from
            dependencies of the module for the generated header of the target
            being compiled.
        include_swiftdoc: If .swiftdoc file should be included or not.
        include_swiftsourceinfo: If .swiftsourceinfo file should be included or not.
        module_name: The name of the Swift module being compiled.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being
            built.
        user_compile_flags: The flags that will be passed to the compile action,
            which are scanned to determine whether a single frontend invocation
            will be used or not.

    Returns:
        A tuple containing two elements:

        *   A `struct` that should be merged into the `prerequisites` of the
            compilation action.
        *   A list of `File`s that represent additional inputs that are not
            needed as configurator prerequisites nor are processed further but
            which should also be tracked as outputs of the compilation action.
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
    swiftdoc_file = _declare_target_scoped_file(
        actions = actions,
        add_target_name_to_output_path = add_target_name_to_output_path,
        target_name = target_name,
        basename = "{}.swiftdoc".format(module_name),
    ) if include_swiftdoc else None

    swiftsourceinfo_file = _declare_target_scoped_file(
        actions = actions,
        add_target_name_to_output_path = add_target_name_to_output_path,
        target_name = target_name,
        basename = "{}.swiftsourceinfo".format(module_name),
    ) if include_swiftsourceinfo else None

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
        # Collect the names of Clang modules that the module being built
        # directly depends on.
        dependent_module_names = sets.make()
        for swift_info in generated_module_deps_swift_infos:
            for module in swift_info.direct_modules:
                if module.clang:
                    sets.insert(dependent_module_names, module.name)

        generated_module_map = actions.declare_file(
            "{}_modulemap/_/module.modulemap".format(target_name),
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

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just
        # declare the output file that the compiler will generate and there are
        # no other partial outputs.
        object_files = [actions.declare_file("{}.o".format(target_name))]
        ast_files = [_declare_per_source_ast_file(
            actions = actions,
            target_name = target_name,
            src = srcs[0],
        )]
        other_outputs = []
        const_values_files = [
            actions.declare_file("{}.swiftconstvalues".format(target_name)),
        ]
        output_file_map = None
        derived_files_output_file_map = None
    else:
        split_derived_file_generation = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_SPLIT_DERIVED_FILES_GENERATION,
        )

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
        )
        object_files = output_info.object_files
        ast_files = output_info.ast_files
        other_outputs = output_info.other_outputs
        const_values_files = output_info.const_values_files
        output_file_map = output_info.output_file_map
        derived_files_output_file_map = output_info.derived_files_output_file_map

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
    else:
        indexstore_directory = None

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE__SUPPORTS_MACROS,
    ) and not is_feature_enabled(
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
    return compile_outputs, other_outputs

def _intermediate_frontend_file_path(target_name, src):
    """Returns the path to the directory for intermediate compile outputs.

    This is a helper function and is not exported in the `derived_files` module.

    Args:
        target_name: The name of hte target being built.
        src: A `File` representing the source file whose intermediate frontend
            artifacts path should be returned.

    Returns:
        The path to the directory where intermediate artifacts for the given
        target and source file should be stored.
    """
    objs_dir = "{}_objs".format(target_name)

    owner_rel_path = owner_relative_path(src).replace(" ", "__SPACE__")
    safe_name = paths.basename(owner_rel_path)

    return paths.join(objs_dir, paths.dirname(owner_rel_path)), safe_name

def _declare_per_source_ast_file(*, actions, target_name, src):
    """Declares a file for an ast file during compilation.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File` where the given src's AST will be dumped to.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(paths.join(dirname, "{}.ast".format(basename)))

def _declare_per_source_bc_file(*, actions, target_name, src):
    """Declares a file for a per-source llvm bc file during compilation.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(paths.join(dirname, "{}.bc".format(basename)))

def _declare_per_source_object_file(*, actions, target_name, src):
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
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(paths.join(dirname, "{}.o".format(basename)))

def _intermediate_per_source_swift_const_values_file(
        *,
        actions,
        target_name,
        src):
    """Declares a file for a per-source Swift const values file during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled); in that case, there
    is a `.swiftconstvalues` file produced for each source file, rather than a single
    `.swiftconstvalues` for the entire module.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.
        src: A `File` representing the source file being compiled.

    Returns:
        The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(
        paths.join(dirname, "{}.swiftconstvalues".format(basename)),
    )

def _declare_multiple_outputs_and_write_output_file_map(
        actions,
        extract_const_values,
        is_wmo,
        emits_bc,
        split_derived_file_generation,
        srcs,
        target_name):
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

    Returns:
        A `struct` with the following fields:

        *   `object_files`: A list of object files that were declared and
            recorded in the output file map, which should be tracked as outputs
            of the compilation action.
        *   `other_outputs`: A list of additional output files that were
            declared and recorded in the output file map, which should be
            tracked as outputs of the compilation action.
        *   `output_file_map`: A `File` that represents the output file map that
            was written and that should be passed as an input to the compilation
            action via the `-output-file-map` flag.
        *   `derived_files_output_file_map`: A `File` that represents the
            output file map that should be passed to derived file generation
            actions instead of the default `output_file_map` that is used for
            producing objects only.
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
    # `output_map_file` and `derived_files_output_map_file`.
    output_map = {}
    whole_module_map = {}
    derived_files_output_map = {}

    # Output files that will be emitted by the compiler.
    output_objs = []
    const_values_files = []

    # Additional files, such as partial Swift modules, that must be declared as
    # action outputs although they are not processed further.
    other_outputs = []

    # AST files that are available in the swift_ast_file output group
    ast_files = []

    if extract_const_values and is_wmo:
        const_values_file = actions.declare_file(
            "{}.swiftconstvalues".format(target_name),
        )
        const_values_files.append(const_values_file)
        whole_module_map["const-values"] = const_values_file.path

    for src in srcs:
        src_output_map = {}

        if extract_const_values and not is_wmo:
            const_values_file = _intermediate_per_source_swift_const_values_file(
                actions = actions,
                target_name = target_name,
                src = src,
            )
            const_values_files.append(const_values_file)
            src_output_map["const-values"] = const_values_file.path

        if emits_bc:
            # Declare the llvm bc file (there is one per source file).
            obj = _declare_per_source_bc_file(
                actions = actions,
                target_name = target_name,
                src = src,
            )
            output_objs.append(obj)
            src_output_map["llvm-bc"] = obj.path
        else:
            # Declare the object file (there is one per source file).
            obj = _declare_per_source_object_file(
                actions = actions,
                target_name = target_name,
                src = src,
            )
            output_objs.append(obj)
            src_output_map["object"] = obj.path

        ast = _declare_per_source_ast_file(
            actions = actions,
            target_name = target_name,
            src = src,
        )
        ast_files.append(ast)
        src_output_map["ast-dump"] = ast.path
        output_map[src.path] = struct(**src_output_map)

    actions.write(
        content = json.encode(struct(**output_map)),
        output = output_map_file,
    )

    if split_derived_file_generation:
        actions.write(
            content = json.encode(struct(**derived_files_output_map)),
            output = derived_files_output_map_file,
        )

    return struct(
        const_values_files = const_values_files,
        ast_files = ast_files,
        object_files = output_objs,
        other_outputs = other_outputs,
        output_file_map = output_map_file,
        derived_files_output_file_map = derived_files_output_map_file,
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
    or is equal to 1); otherwise, it emits one object file per source file. It
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
