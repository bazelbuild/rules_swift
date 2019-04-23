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

"""A resilient API layer wrapping compilation and other logic for Swift.

This module is meant to be used by custom rules that need to compile Swift code
and cannot simply rely on writing a macro that wraps `swift_library`. For
example, `swift_proto_library` generates Swift source code from `.proto` files
and then needs to compile them. This module provides that lower-level interface.

Do not load this file directly; instead, load the top-level `swift.bzl` file,
which exports the `swift_common` module.
"""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:types.bzl", "types")
load(
    ":actions.bzl",
    "run_toolchain_action",
    "run_toolchain_shell_action",
    "run_toolchain_swift_action",
)
load(":archiving.bzl", "register_static_archive_action")
load(":attrs.bzl", "swift_common_rule_attrs")
load(
    ":compiling.bzl",
    "collect_transitive_compile_inputs",
    "declare_compile_outputs",
    "find_swift_version_copt_value",
    "new_objc_provider",
    "objc_compile_requirements",
    "register_autolink_extract_action",
    "write_objc_header_module_map",
)
load(":debugging.bzl", "ensure_swiftmodule_is_embedded")
load(":deps.bzl", "legacy_build_swift_info")
load(":derived_files.bzl", "derived_files")
load(
    ":features.bzl",
    "SWIFT_FEATURE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_COVERAGE",
    "SWIFT_FEATURE_DBG",
    "SWIFT_FEATURE_DEBUG_PREFIX_MAP",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_ENABLE_TESTING",
    "SWIFT_FEATURE_FASTBUILD",
    "SWIFT_FEATURE_FULL_DEBUG_INFO",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_HEADER",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_OPT",
    "SWIFT_FEATURE_OPT_USES_WMO",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
)
load(
    ":providers.bzl",
    "SwiftClangModuleInfo",
    "SwiftInfo",
    "SwiftToolchainInfo",
    "merge_swift_clang_module_infos",
)

# The Swift copts to pass for various sanitizer features.
_SANITIZER_FEATURE_FLAG_MAP = {
    "asan": ["-sanitize=address"],
    "tsan": ["-sanitize=thread"],
}

def _create_swift_info(
        additional_inputs = [],
        defines = [],
        libraries = [],
        linkopts = [],
        module_name = None,
        swiftdocs = [],
        swiftmodules = [],
        swift_version = None):
    """Creates a new `SwiftInfo` provider with the given values.

    This function is recommended instead of directly creating a `SwiftInfo` provider because it
    encodes reasonable defaults for fields that some rules may not be interested in and ensures
    that the direct and transitive fields are set consistently.

    Args:
        additional_inputs: A list of additional input files passed into a library or binary target
            via the `swiftc_inputs` attribute.
        defines: A list of defines that will be provided as `copts` of the target being built.
        libraries: A list of `.a` files that are the direct outputs of the target being built.
        linkopts: A list of linker flags that will be passed to the linker when the target being
            built is linked into a binary.
        module_name: A string containing the name of the Swift module, or `None` if the provider
            does not represent a compiled module (this happens, for example, with `proto_library`
            targets that act as "collectors" of other modules but have no sources of their own).
        swiftdocs: A list of `.swiftdoc` files that are the direct outputs of the target being
            built.
        swiftmodules: A list of `.swiftmodule` files that are the direct outputs of the target
            being built.
        swift_version: A string containing the value of the `-swift-version` flag used when
            compiling this target, or `None` if it was not set or is not relevant.

    Returns:
        A new `SwiftInfo` provider with the given values.
    """
    return SwiftInfo(
        direct_defines = defines,
        direct_libraries = libraries,
        direct_linkopts = linkopts,
        direct_swiftdocs = swiftdocs,
        direct_swiftmodules = swiftmodules,
        module_name = module_name,
        swift_version = swift_version,
        transitive_additional_inputs = depset(direct = additional_inputs),
        transitive_defines = depset(direct = defines),
        transitive_libraries = depset(direct = libraries, order = "topological"),
        transitive_linkopts = depset(direct = linkopts),
        transitive_swiftdocs = depset(direct = swiftdocs),
        transitive_swiftmodules = depset(direct = swiftmodules),
    )

def _compilation_attrs(additional_deps_aspects = []):
    """Returns an attribute dictionary for rules that compile Swift into objects.

    The returned dictionary contains the subset of attributes that are shared by
    the `swift_binary`, `swift_library`, and `swift_test` rules that deal with
    inputs and options for compilation. Users who are authoring custom rules that
    compile Swift code but not as a library can add this dictionary to their own
    rule's attributes to give it a familiar API.

    Do note, however, that it is the responsibility of the rule implementation to
    retrieve the values of those attributes and pass them correctly to the other
    `swift_common` APIs.

    There is a hierarchy to the attribute sets offered by the `swift_common` API:

    1. If you only need access to the toolchain for its tools and libraries but
       are not doing any compilation, use `toolchain_attrs`.
    2. If you need to invoke compilation actions but are not making the resulting
       object files into a static or shared library, use `compilation_attrs`.
    3. If you want to provide a rule interface that is suitable as a drop-in
       replacement for `swift_library`, use `library_rule_attrs`.

    Each of the attribute functions in the list above also contains the attributes
    from the earlier items in the list.

    Args:
      additional_deps_aspects: A list of additional aspects that should be applied
          to `deps`. Defaults to the empty list. These must be passed by the
          individual rules to avoid potential circular dependencies between the API
          and the aspects; the API loaded the aspects directly, then those aspects
          would not be able to load the API.

    Returns:
      A new attribute dictionary that can be added to the attributes of a custom
      build rule to provide a similar interface to `swift_binary`,
      `swift_library`, and `swift_test`.
    """
    return dicts.add(
        swift_common_rule_attrs(additional_deps_aspects = additional_deps_aspects),
        _toolchain_attrs(),
        {
            "srcs": attr.label_list(
                flags = ["DIRECT_COMPILE_TIME_INPUT"],
                allow_files = ["swift"],
                doc = """
A list of `.swift` source files that will be compiled into the library.
""",
            ),
            "copts": attr.string_list(
                doc = """
Additional compiler options that should be passed to `swiftc`. These strings are
subject to `$(location ...)` expansion.
""",
            ),
            "defines": attr.string_list(
                doc = """
A list of defines to add to the compilation command line.

Note that unlike C-family languages, Swift defines do not have values; they are
simply identifiers that are either defined or undefined. So strings in this list
should be simple identifiers, **not** `name=value` pairs.

Each string is prepended with `-D` and added to the command line. Unlike
`copts`, these flags are added for the target and every target that depends on
it, so use this attribute with caution. It is preferred that you add defines
directly to `copts`, only using this feature in the rare case that a library
needs to propagate a symbol up to those that depend on it.
""",
            ),
            "module_name": attr.string(
                doc = """
The name of the Swift module being built.

If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading `//` and replacing `/`, `:`, and other
non-identifier characters with underscores.
""",
            ),
            "swiftc_inputs": attr.label_list(
                allow_files = True,
                doc = """
Additional files that are referenced using `$(location ...)` in attributes that
support location expansion.
""",
            ),
        },
    )

def _compilation_mode_copts(feature_configuration):
    """Returns `swiftc` compilation flags that match the current compilation mode.

    Args:
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`.

    Returns:
      A list of strings containing copts that should be passed to Swift.
    """
    is_dbg = _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_DBG,
    )
    is_fastbuild = _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_FASTBUILD,
    )
    is_opt = _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OPT,
    )
    wants_full_debug_info = _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_FULL_DEBUG_INFO,
    )

    # Safety check that exactly one of these features is set; the user shouldn't mess with them.
    if int(is_dbg) + int(is_fastbuild) + int(is_opt) != 1:
        fail("Exactly one of the features `swift.{dbg,fastbuild,opt}` must be enabled.")

    # The combinations of flags used here mirror the descriptions of these
    # compilation modes given in the Bazel documentation:
    # https://docs.bazel.build/versions/master/user-manual.html#flag--compilation_mode
    flags = []
    if is_opt:
        flags.extend(["-O", "-DNDEBUG"])
        if _is_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_OPT_USES_WMO,
        ):
            flags.append("-whole-module-optimization")

    elif is_dbg or is_fastbuild:
        # The Swift compiler only serializes debugging options in narrow
        # circumstances (for example, for application binaries). Since we almost
        # exclusively just compile to object files directly, we need to manually
        # pass the following frontend option to ensure that LLDB has the necessary
        # import search paths to find definitions during debugging.
        flags.extend(["-Onone", "-DDEBUG", "-Xfrontend", "-serialize-debugging-options"])

    if _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_ENABLE_TESTING,
    ):
        flags.append("-enable-testing")

    # The combination of dsymutil and -gline-tables-only appears to cause
    # spurious warnings about symbols in the debug map, so if the caller is
    # requesting dSYMs, then force `-g` regardless of compilation mode.
    if is_dbg or wants_full_debug_info:
        flags.append("-g")
    elif is_fastbuild:
        flags.append("-gline-tables-only")

    return flags

def _coverage_copts(feature_configuration):
    """Returns `swiftc` compilation flags for code converage if enabled.

    Args:
        feature_configuration: The feature configuration.

    Returns:
        A list of compiler flags that enable code coverage if requested.
    """
    if _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_COVERAGE,
    ):
        return ["-profile-generate", "-profile-coverage-mapping"]
    return []

def _is_debugging(feature_configuration):
    """Returns `True` if the current compilation mode produces debug info.

    We replicate the behavior of the C++ build rules for Swift, which are described here:
    https://docs.bazel.build/versions/master/user-manual.html#flag--compilation_mode

    Args:
        feature_configuration: The feature configuration.

    Returns:
        `True` if the current compilation mode produces debug info.
    """
    return (
        _is_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_DBG,
        ) or _is_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_FASTBUILD,
        )
    )

def _sanitizer_copts(feature_configuration):
    """Returns `swiftc` compilation flags for any requested sanitizer features.

    Args:
      feature_configuration: The feature configuration.

    Returns:
      A list of compiler flags that enable the requested sanitizers for a Swift
      compilation action.
    """
    copts = []
    for (feature_name, flags) in _SANITIZER_FEATURE_FLAG_MAP.items():
        if swift_common.is_enabled(
            feature_configuration = feature_configuration,
            feature_name = feature_name,
        ):
            copts.extend(flags)
    return copts

def _global_module_cache_path(bin_dir):
    """Returns the path to the location where the Swift compiler should cache modules.

    Note that the use of this cache is non-hermetic; the cached modules are not declared inputs or
    outputs and they are not wiped between builds. The cache is purely a build performance
    optimization that reduces the need for large dependency graphs to repeatedly parse the same
    content multiple times.

    Args:
      bin_dir: The Bazel `*-bin` directory root where the module cache directory should be created.
          By placing it in `*-bin` (instead of the default, a path based on `/tmp/*`), the cache
          will be reliably cleaned when invoking `bazel clean`.

    Returns:
      The path to the module cache.
    """

    # This path explicitly differs from the one used for Objective-C. This is because the
    # Clang invocation for Objective-C does not produce the same hashes as the invocation used
    # internally by Swift's ClangImporter. This means that the cached modules will never actually
    # be shared, and making the paths the same would be at best useless and at worse actively
    # harmful if there ever were to be a collision. We can revisit this decision if it ever
    # becomes possible to reliably share module caches between Clang and Swift.
    return paths.join(bin_dir.path, "_swift_module_cache")

def _is_wmo(copts, feature_configuration):
    """Returns a value indicating whether a compilation will use whole module optimization.

    Args:
        copts: A list of compiler flags to scan for WMO usage.
        feature_configuration: The Swift feature configuration, as returned from
            `swift_common.configure_features`.

    Returns:
        True if WMO is enabled in the given list of flags.
    """

    # First, check the feature configuration to see if the current compilation mode implies
    # whole-module-optimization.
    is_opt = _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OPT,
    )
    opt_uses_wmo = _is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OPT_USES_WMO,
    )
    if is_opt and opt_uses_wmo:
        return True

    # Otherwise, check any explicit copts the user may have set on the target or command line.
    return ("-wmo" in copts or
            "-whole-module-optimization" in copts or
            "-force-single-frontend-invocation" in copts)

def _cc_feature_configuration(feature_configuration):
    """Returns the C++ feature configuration nested inside the given Swift feature configuration.

    Args:
        feature_configuration: The Swift feature configuration, as returned from
            `swift_common.configure_features`.

    Returns:
        A C++ `FeatureConfiguration` value (see `cc_common` for more information).
    """
    return feature_configuration.cc_feature_configuration

def _compile_as_objects(
        actions,
        arguments,
        feature_configuration,
        module_name,
        srcs,
        target_name,
        toolchain,
        additional_input_depsets = [],
        additional_outputs = [],
        bin_dir = None,
        copts = [],
        defines = [],
        deps = [],
        genfiles_dir = None):
    """Compiles Swift source files into object files (and optionally a module).

    Args:
      actions: The context's `actions` object.
      arguments: A list of `Args` objects that provide additional arguments to the
          compiler, not including the `copts` list.
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`.
      module_name: The name of the Swift module being compiled. This must be
          present and valid; use `swift_common.derive_module_name` to generate a
          default from the target's label if needed.
      srcs: The Swift source files to compile.
      target_name: The name of the target for which the code is being compiled,
          which is used to determine unique file paths for the outputs.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      additional_input_depsets: A list of `depset`s of `File`s representing
          additional input files that need to be passed to the Swift compile
          action because they are referenced by compiler flags.
      additional_outputs: A list of `File`s representing files that should be
          treated as additional outputs of the compilation action.
      bin_dir: The Bazel `*-bin` directory root. If provided, its path is used to
          store the cache for modules precompiled by Swift's ClangImporter.
      copts: A list (**not** an `Args` object) of compiler flags that apply to the
          target being built. These flags, along with those from Bazel's Swift
          configuration fragment (i.e., `--swiftcopt` command line flags) are
          scanned to determine whether whole module optimization is being
          requested, which affects the nature of the output files.
      defines: Symbols that should be defined by passing `-D` to the compiler.
      deps: Dependencies of the target being compiled. These targets must
          propagate one of the following providers: `CcInfo`,
          `SwiftClangModuleInfo`, `SwiftInfo`, or `apple_common.Objc`.
      genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its path
          is added to ClangImporter's header search paths for compatibility with
          Bazel's C++ and Objective-C rules which support inclusions of generated
          headers from that location.

    Returns:
      A `struct` containing the following fields:

      * `compile_inputs`: A `depset` of `File`s representing the full collection
        of files that were used as inputs to the compile action. This can be used
        if those files need to also be made available to subsequent link actions.
      * `linker_flags`: A list of strings representing additional flags that
        should be passed to the linker when linking these objects into a binary.
      * `linker_inputs`: A list of `File`s representing additional input files
        (such as those referenced in `linker_flags`) that need to be available to
        the linker action when linking these objects into a binary.
      * `output_doc`: The `.swiftdoc` file that was produced by the compiler.
      * `output_groups`: A dictionary of output groups that should be returned by
        the calling rule through the `OutputGroupInfo` provider.
      * `output_module`: The `.swiftmodule` file that was produced by the
        compiler.
      * `output_objects`: The object (`.o`) files that were produced by the
        compiler.
    """

    # Force threaded mode for WMO builds, using the same number of cores that is
    # on a Mac Pro for historical reasons.
    # TODO(b/32571265): Generalize this based on platform and core count when an
    # API to obtain this is available.
    if _is_wmo(copts + toolchain.command_line_copts, feature_configuration):
        # We intentionally don't use `+=` or `extend` here to ensure that a
        # copy is made instead of extending the original.
        copts = copts + ["-num-threads", "12"]

    compile_reqs = declare_compile_outputs(
        actions = actions,
        copts = copts + toolchain.command_line_copts,
        srcs = srcs,
        target_name = target_name,
        index_while_building = swift_common.is_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_INDEX_WHILE_BUILDING,
        ),
    )
    output_objects = compile_reqs.output_objects

    out_module = derived_files.swiftmodule(actions, module_name = module_name)
    out_doc = derived_files.swiftdoc(actions, module_name = module_name)

    wrapper_args = actions.args()
    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE,
    ):
        # If bin_dir is not provided, then we don't pass any special flags to the compiler,
        # letting it decide where the cache should live. This is usually somewhere in the system
        # temporary directory.
        if bin_dir:
            wrapper_args.add("-module-cache-path", _global_module_cache_path(bin_dir))
    else:
        wrapper_args.add("-Xwrapped-swift=-ephemeral-module-cache")

    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_DEBUG_PREFIX_MAP,
    ):
        wrapper_args.add("-Xwrapped-swift=-debug-prefix-pwd-is-dot")

    compile_args = actions.args()
    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_RESPONSE_FILES,
    ):
        compile_args.use_param_file("@%s", use_always = True)

    compile_args.add("-emit-object")
    compile_args.add_all(compile_reqs.args)
    compile_args.add("-emit-module-path")
    compile_args.add(out_module)

    basic_inputs = _swiftc_command_line_and_inputs(
        args = compile_args,
        module_name = module_name,
        srcs = srcs,
        toolchain = toolchain,
        additional_input_depsets = additional_input_depsets,
        copts = copts,
        defines = defines,
        deps = deps,
        feature_configuration = feature_configuration,
        genfiles_dir = genfiles_dir,
    )

    all_inputs = depset(
        transitive = [basic_inputs, depset(direct = compile_reqs.compile_inputs)],
    )
    compile_outputs = ([out_module, out_doc] + output_objects +
                       compile_reqs.other_outputs) + additional_outputs

    if toolchain.swift_worker:
        execution_requirements = {"supports-workers": "1"}
        tools = [toolchain.swift_worker]
    else:
        execution_requirements = {}
        tools = []

    run_toolchain_swift_action(
        actions = actions,
        arguments = [wrapper_args, compile_args] + arguments,
        execution_requirements = execution_requirements,
        inputs = all_inputs,
        mnemonic = "SwiftCompile",
        outputs = compile_outputs,
        progress_message = "Compiling Swift module {}".format(module_name),
        swift_tool = "swiftc",
        toolchain = toolchain,
        tools = tools,
    )

    linker_flags = []
    linker_inputs = []

    # Ensure that the .swiftmodule file is embedded in the final library or binary
    # for debugging purposes.
    if _is_debugging(feature_configuration = feature_configuration):
        module_embed_results = ensure_swiftmodule_is_embedded(
            actions = actions,
            swiftmodule = out_module,
            target_name = target_name,
            toolchain = toolchain,
        )
        linker_flags.extend(module_embed_results.linker_flags)
        linker_inputs.extend(module_embed_results.linker_inputs)
        output_objects.extend(module_embed_results.objects_to_link)

    # Invoke an autolink-extract action for toolchains that require it.
    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_AUTOLINK_EXTRACT,
    ):
        autolink_file = derived_files.autolink_flags(
            actions,
            target_name = target_name,
        )
        register_autolink_extract_action(
            actions = actions,
            module_name = module_name,
            objects = output_objects,
            output = autolink_file,
            toolchain = toolchain,
        )
        linker_flags.append("@{}".format(autolink_file.path))
        linker_inputs.append(autolink_file)

    return struct(
        compile_inputs = all_inputs,
        linker_flags = linker_flags,
        linker_inputs = linker_inputs,
        output_doc = out_doc,
        output_groups = compile_reqs.output_groups,
        output_module = out_module,
        output_objects = output_objects,
    )

def _compile_as_library(
        actions,
        bin_dir,
        feature_configuration,
        label,
        module_name,
        srcs,
        toolchain,
        additional_inputs = [],
        alwayslink = False,
        copts = [],
        defines = [],
        deps = [],
        genfiles_dir = None,
        library_name = None,
        linkopts = []):
    """Compiles Swift source files into static and/or shared libraries.

    This is a high-level API that wraps the compilation and library creation steps
    based on the provided input arguments, and is likely suitable for most common
    purposes.

    If the toolchain supports Objective-C interop, then this function also
    generates an Objective-C header file for the library and returns an `Objc`
    provider that allows other `objc_library` targets to depend on it.

    Args:
      actions: The rule context's `actions` object.
      bin_dir: The Bazel `*-bin` directory root.
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`.
      label: The target label for which the code is being compiled, which is used
          to determine unique file paths for the outputs.
      module_name: The name of the Swift module being compiled. This must be
          present and valid; use `swift_common.derive_module_name` to generate a
          default from the target's label if needed.
      srcs: The Swift source files to compile.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      additional_inputs: A list of `File`s representing additional inputs that
          need to be passed to the Swift compile action because they are
          referenced in compiler flags.
      alwayslink: Indicates whether the object files in the library should always
          be always be linked into any binaries that depend on it, even if some
          contain no symbols referenced by the binary.
      copts: Additional flags that should be passed to `swiftc`.
      defines: Symbols that should be defined by passing `-D` to the compiler.
      deps: Dependencies of the target being compiled. These targets must
          propagate one of the following providers: `CcInfo`,
          `SwiftClangModuleInfo`, `SwiftInfo`, or `apple_common.Objc`.
      genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its path
          is added to ClangImporter's header search paths for compatibility with
          Bazel's C++ and Objective-C rules which support inclusions of generated
          headers from that location.
      library_name: The name that should be substituted for the string `{name}` in
          `lib{name}.a`, which will be the output of this compilation. If this is
          not specified or is falsy, then the default behavior is to simply use
          the name of the build target.
      linkopts: Additional flags that should be passed to the linker when the
          target being compiled is linked into a binary. These options are not
          used directly by any action registered by this function, but they are
          added to the `SwiftInfo` provider that it returns so that the linker
          flags can be propagated to dependent targets.

    Returns:
      A `struct` containing the following fields:

      * `compile_inputs`: A `depset` of `File`s representing the full collection
        of files that were used as inputs to the compile action. This can be used
        if those files need to also be made available to subsequent link actions.
      * `output_archive`: The static archive (`.a`) that was produced by the
        archiving step after compilation.
      * `output_doc`: The `.swiftdoc` file that was produced by the compiler.
      * `output_header`: The generated Swift bridging header if any, or `None`.
      * `output_groups`: A dictionary of output groups that should be returned by
        the calling rule through the `OutputGroupInfo` provider.
      * `output_module`: The `.swiftmodule` file that was produced by the
        compiler.
      * `providers`: A list of providers that should be returned by the calling
        rule. This includes the `SwiftInfo` provider, and if Objective-C interop
        is enabled on the toolchain, an `apple_common.Objc` provider as well.
    """
    if not module_name:
        fail("'module_name' must be provided. Use " +
             "'swift_common.derive_module_name' if necessary to derive one from " +
             " the target label.")

    all_deps = deps + toolchain.implicit_deps

    if not library_name:
        library_name = label.name
    out_archive = derived_files.static_archive(
        actions,
        alwayslink = alwayslink,
        link_name = library_name,
    )

    # Register the compilation actions to get an object file (.o) for the Swift
    # code, along with its swiftmodule and swiftdoc.
    library_copts = actions.args()
    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_USE_RESPONSE_FILES,
    ):
        library_copts.use_param_file("@%s", use_always = True)

    # Builds on Apple platforms typically don't use `swift_binary`; they have
    # different linking logic to produce fat binaries. This means that all such
    # application code will typically be in a `swift_library` target, and that
    # includes a possible custom main entry point. For this reason, we need to
    # support the creation of `swift_library` targets containing a `main.swift`
    # file, which should *not* pass the `-parse-as-library` flag to the compiler.
    use_parse_as_library = True
    for src in srcs:
        if src.basename == "main.swift":
            use_parse_as_library = False
            break
    if use_parse_as_library:
        library_copts.add("-parse-as-library")

    objc_header = None
    output_module_map = None
    additional_outputs = []
    compile_input_depsets = [depset(direct = additional_inputs)]

    generates_header = not swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_NO_GENERATED_HEADER,
    )
    if generates_header and toolchain.supports_objc_interop:
        # Generate a Swift bridging header for this library so that it can be
        # included by Objective-C code that may depend on it.
        objc_header = derived_files.objc_header(actions, target_name = label.name)
        library_copts.add("-emit-objc-header-path")
        library_copts.add(objc_header)
        additional_outputs.append(objc_header)

        # Create a module map for the generated header file. This ensures that
        # inclusions of it are treated modularly, not textually.
        #
        # Caveat: Generated module maps are incompatible with the hack that some
        # folks are using to support mixed Objective-C and Swift modules. This trap
        # door lets them escape the module redefinition error, with the caveat that
        # certain import scenarios could lead to incorrect behavior because a header
        # can be imported textually instead of modularly.
        if not swift_common.is_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_NO_GENERATED_MODULE_MAP,
        ):
            output_module_map = derived_files.module_map(
                actions,
                target_name = label.name,
            )
            write_objc_header_module_map(
                actions = actions,
                module_name = module_name,
                objc_header = objc_header,
                output = output_module_map,
            )

    compile_results = _compile_as_objects(
        actions = actions,
        arguments = [library_copts],
        bin_dir = bin_dir,
        copts = copts,
        defines = defines,
        feature_configuration = feature_configuration,
        module_name = module_name,
        srcs = srcs,
        target_name = label.name,
        toolchain = toolchain,
        additional_input_depsets = compile_input_depsets,
        additional_outputs = additional_outputs,
        deps = deps,
        genfiles_dir = genfiles_dir,
    )

    # Create an archive that contains the compiled .o files.
    register_static_archive_action(
        actions = actions,
        cc_feature_configuration = _cc_feature_configuration(
            feature_configuration = feature_configuration,
        ),
        mnemonic = "SwiftArchive",
        objects = compile_results.output_objects,
        output = out_archive,
        progress_message = "Linking {}".format(out_archive.short_path),
        swift_toolchain = toolchain,
    )

    # TODO(b/130741225): Move this logic out of the API and have the rules themselves manipulate
    # providers.
    providers = [
        legacy_build_swift_info(
            deps = all_deps,
            direct_additional_inputs = additional_inputs + compile_results.linker_inputs,
            direct_defines = defines,
            direct_libraries = [out_archive],
            direct_linkopts = linkopts + compile_results.linker_flags,
            direct_swiftdocs = [compile_results.output_doc],
            direct_swiftmodules = [compile_results.output_module],
            module_name = module_name,
            swift_version = find_swift_version_copt_value(copts),
        ),
    ]

    # Propagate an `objc` provider if the toolchain supports Objective-C interop,
    # which allows `objc_library` targets to import `swift_library` targets.
    if toolchain.supports_objc_interop:
        providers.append(new_objc_provider(
            defines = defines,
            deps = all_deps,
            include_path = bin_dir.path,
            link_inputs = compile_results.linker_inputs,
            linkopts = compile_results.linker_flags,
            module_map = output_module_map,
            static_archives = [out_archive],
            swiftmodules = [compile_results.output_module],
            objc_header = objc_header,
        ))

    # Only propagate `SwiftClangModuleInfo` if any of our deps does.
    if any([SwiftClangModuleInfo in dep for dep in all_deps]):
        clang_module = merge_swift_clang_module_infos(all_deps)
        providers.append(clang_module)

    return struct(
        compile_inputs = compile_results.compile_inputs,
        output_archive = out_archive,
        output_doc = compile_results.output_doc,
        output_groups = compile_results.output_groups,
        output_header = objc_header,
        output_module = compile_results.output_module,
        providers = providers,
    )

def _configure_features(swift_toolchain, requested_features = [], unsupported_features = []):
    """Creates a feature configuration that should be passed to other Swift build APIs.

    This function calls through to `cc_common.configure_features` to configure underlying C++
    features as well, and nests the C++ feature configuration inside the Swift one. Users who need
    to call C++ APIs that require a feature configuration can extract it by calling
    `swift_common.cc_feature_configuration(feature_configuration)`.

    Args:
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain being used to build.
            The C++ toolchain associated with the Swift toolchain is used to create the underlying
            C++ feature configuration.
        requested_features: The list of features to be enabled. This is typically obtained using
            the `ctx.features` field in a rule implementation function.
        unsupported_features: The list of features that are unsupported by the current rule. This
            is typically obtained using the `ctx.disabled_features` field in a rule implementation
            function.

    Returns:
        An opaque value representing the feature configuration that can be passed to other
        `swift_common` functions.
    """

    # The features to enable for a particular rule/target are the ones requested by the toolchain,
    # plus the ones requested by the target itself, *minus* any that are explicitly disabled on the
    # target itself.
    requested_features_set = sets.make(swift_toolchain.requested_features)
    requested_features_set = sets.union(requested_features_set, sets.make(requested_features))
    requested_features_set = sets.difference(
        requested_features_set,
        sets.make(unsupported_features),
    )
    all_requested_features = sets.to_list(requested_features_set)

    all_unsupported_features = collections.uniq(
        swift_toolchain.unsupported_features + unsupported_features,
    )

    # Verify the consistency of Swift features requested vs. those that are not supported by the
    # toolchain. We don't need to do this for C++ features because `cc_common.configure_features`
    # handles verifying those.
    for feature in requested_features:
        if feature.startswith("swift.") and feature in all_unsupported_features:
            fail("Feature '{}' was requested, ".format(feature) +
                 "but it is not supported by the current toolchain or rule.")

    cc_feature_configuration = cc_common.configure_features(
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        requested_features = all_requested_features,
        unsupported_features = all_unsupported_features,
    )
    return struct(
        cc_feature_configuration = cc_feature_configuration,
        requested_features = all_requested_features,
        unsupported_features = all_unsupported_features,
    )

def _derive_module_name(*args):
    """Returns a derived module name from the given build label.

    For targets whose module name is not explicitly specified, the module name is
    computed by creating an underscore-delimited string from the components of the
    label, replacing any non-identifier characters also with underscores.

    This mapping is not intended to be reversible.

    Args:
      *args: Either a single argument of type `Label`, or two arguments of type
        `str` where the first argument is the package name and the second
        argument is the target name.

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
        fail("derive_module_name may only be called with a single argument of " +
             "type 'Label' or two arguments of type 'str'")

    package_part = (package.lstrip("//").replace("/", "_").replace("-", "_").replace(".", "_"))
    name_part = name.replace("-", "_")
    if package_part:
        return package_part + "_" + name_part
    return name_part

def _is_enabled(feature_configuration, feature_name):
    """Returns `True` if the given feature is enabled in the feature configuration.

    This function handles both Swift-specific features and C++ features so that users do not have
    to manually extract the C++ configuration in order to check it.

    Args:
        feature_configuration: The Swift feature configuration, as returned by
            `swift_common.configure_features`.
        feature_name: The name of the feature to check.

    Returns:
        `True` if the given feature is enabled in the feature configuration.
    """
    if feature_name.startswith("swift."):
        return feature_name in feature_configuration.requested_features
    else:
        return cc_common.is_enabled(
            feature_configuration = _cc_feature_configuration(feature_configuration),
            feature_name = feature_name,
        )

def _library_rule_attrs(additional_deps_aspects = []):
    """Returns an attribute dictionary for `swift_library`-like rules.

    The returned dictionary contains the same attributes that are defined by the
    `swift_library` rule (including the private `_toolchain` attribute that
    specifies the toolchain dependency). Users who are authoring custom rules can
    use this dictionary verbatim or add other custom attributes to it in order to
    make their rule a drop-in replacement for `swift_library` (for example, if
    writing a custom rule that does some preprocessing or generation of sources
    and then compiles them).

    Do note, however, that it is the responsibility of the rule implementation to
    retrieve the values of those attributes and pass them correctly to the other
    `swift_common` APIs.

    There is a hierarchy to the attribute sets offered by the `swift_common` API:

    1. If you only need access to the toolchain for its tools and libraries but
       are not doing any compilation, use `toolchain_attrs`.
    2. If you need to invoke compilation actions but are not making the resulting
       object files into a static or shared library, use `compilation_attrs`.
    3. If you want to provide a rule interface that is suitable as a drop-in
       replacement for `swift_library`, use `library_rule_attrs`.

    Each of the attribute functions in the list above also contains the attributes
    from the earlier items in the list.

    Args:
      additional_deps_aspects: A list of additional aspects that should be applied
          to `deps`. Defaults to the empty list. These must be passed by the
          individual rules to avoid potential circular dependencies between the API
          and the aspects; the API loaded the aspects directly, then those aspects
          would not be able to load the API.

    Returns:
      A new attribute dictionary that can be added to the attributes of a custom
      build rule to provide the same interface as `swift_library`.
    """
    return dicts.add(
        _compilation_attrs(additional_deps_aspects = additional_deps_aspects),
        {
            "linkopts": attr.string_list(
                doc = """
Additional linker options that should be passed to the linker for the binary
that depends on this target. These strings are subject to `$(location ...)`
expansion.
""",
            ),
            "alwayslink": attr.bool(
                default = False,
                doc = """
If true, any binary that depends (directly or indirectly) on this Swift module
will link in all the object files for the files listed in `srcs`, even if some
contain no symbols referenced by the binary. This is useful if your code isn't
explicitly called by code in the binary; for example, if you rely on runtime
checks for protocol conformances added in extensions in the library but do not
directly reference any other symbols in the object file that adds that
conformance.
""",
            ),
        },
    )

def _merge_swift_infos(swift_infos):
    """Merges a list of `SwiftInfo` providers into one.

    Args:
        swift_infos: A sequence of `SwiftInfo`providers to merge.

    Returns:
        A new `SwiftInfo` provider.
    """
    transitive_additional_inputs = []
    transitive_defines = []
    transitive_libraries = []
    transitive_linkopts = []
    transitive_swiftdocs = []
    transitive_swiftmodules = []

    for swift_info in swift_infos:
        transitive_additional_inputs.append(swift_info.transitive_additional_inputs)
        transitive_defines.append(swift_info.transitive_defines)
        transitive_libraries.append(swift_info.transitive_libraries)
        transitive_linkopts.append(swift_info.transitive_linkopts)
        transitive_swiftdocs.append(swift_info.transitive_swiftdocs)
        transitive_swiftmodules.append(swift_info.transitive_swiftmodules)

    return SwiftInfo(
        direct_defines = [],
        direct_libraries = [],
        direct_linkopts = [],
        direct_swiftdocs = [],
        direct_swiftmodules = [],
        module_name = None,
        swift_version = None,
        transitive_additional_inputs = depset(transitive = transitive_additional_inputs),
        transitive_defines = depset(transitive = transitive_defines),
        transitive_libraries = depset(transitive = transitive_libraries),
        transitive_linkopts = depset(transitive = transitive_linkopts),
        transitive_swiftdocs = depset(transitive = transitive_swiftdocs),
        transitive_swiftmodules = depset(transitive = transitive_swiftmodules),
    )

def _swift_runtime_linkopts(is_static, toolchain, is_test = False):
    """Returns the flags that should be passed to `clang` when linking a binary.

    This function provides the appropriate linker arguments to callers who need to
    link a binary using something other than `swift_binary` (for example, an
    application bundle containing a universal `apple_binary`).

    Args:
      is_static: A `Boolean` value indicating whether the binary should be linked
          against the static (rather than the dynamic) Swift runtime libraries.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain whose linker
          options are desired.
      is_test: A `Boolean` value indicating whether the target being linked is a
          test target.

    Returns:
      A `list` of command-line flags that should be passed to `clang` to link
      against the Swift runtime libraries.
    """
    return partial.call(
        toolchain.linker_opts_producer,
        is_static = is_static,
        is_test = is_test,
    )

def _swiftc_command_line_and_inputs(
        args,
        feature_configuration,
        module_name,
        srcs,
        toolchain,
        additional_input_depsets = [],
        copts = [],
        defines = [],
        deps = [],
        genfiles_dir = None):
    """Computes command line arguments and inputs needed to invoke `swiftc`.

    The command line arguments computed by this function are any that do *not*
    require the declaration of new output files. For example, it includes the list
    of frameworks, defines, source files, and other copts, but not flags like the
    output objects or `.swiftmodule` files. The purpose of this is to allow
    (nearly) the same command line that would be passed to the compiler to be
    passed to other tools that require it; the most common application of this is
    for tools that use SourceKit, which need to know the command line in order to
    gather information about dependencies for indexing and code completion.

    Args:
      args: An `Args` object into which the command line arguments will be added.
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`.
      module_name: The name of the Swift module being compiled. This must be
          present and valid; use `swift_common.derive_module_name` to generate a
          default from the target's label if needed.
      srcs: The Swift source files to compile.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      additional_input_depsets: A list of `depset`s of `File`s representing
          additional input files that need to be passed to the Swift compile
          action because they are referenced by compiler flags.
      copts: A list (**not** an `Args` object) of compiler flags that apply to the
          target being built. These flags, along with those from Bazel's Swift
          configuration fragment (i.e., `--swiftcopt` command line flags) are
          scanned to determine whether whole module optimization is being
          requested, which affects the nature of the output files.
      defines: Symbols that should be defined by passing `-D` to the compiler.
      deps: Dependencies of the target being compiled. These targets must
          propagate one of the following providers: `CcInfo`,
          `SwiftClangModuleInfo`, `SwiftInfo`, or `apple_common.Objc`.
      genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its path
          is added to ClangImporter's header search paths for compatibility with
          Bazel's C++ and Objective-C rules which support inclusions of generated
          headers from that location.

    Returns:
      A `depset` containing the full set of files that need to be passed as inputs
      of the Bazel action that spawns a tool with the computed command line (i.e.,
      any source files, referenced module maps and headers, and so forth.)
    """
    all_deps = deps + toolchain.implicit_deps

    args.add("-module-name")
    args.add(module_name)

    args.add_all(_compilation_mode_copts(feature_configuration = feature_configuration))
    args.add_all(_coverage_copts(feature_configuration = feature_configuration))
    args.add_all(_sanitizer_copts(feature_configuration = feature_configuration))
    args.add_all(["-Xfrontend", "-color-diagnostics"])

    if swift_common.is_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
    ):
        args.add_all(collections.before_each(
            "-Xcc",
            ["-Xclang", "-fmodule-map-file-home-is-cwd"],
        ))

    # Do not enable batch mode if the user requested WMO; this silences an "ignoring
    # '-enable-batch-mode' because '-whole-module-optimization' was also specified" warning.
    if (
        not _is_wmo(copts + toolchain.command_line_copts, feature_configuration) and
        swift_common.is_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_ENABLE_BATCH_MODE,
        )
    ):
        args.add("-enable-batch-mode")

    # Add the genfiles directory to ClangImporter's header search paths for
    # compatibility with rules that generate headers there.
    if genfiles_dir:
        args.add_all(["-Xcc", "-iquote{}".format(genfiles_dir.path)])

    input_depsets = list(additional_input_depsets)
    transitive_inputs = collect_transitive_compile_inputs(
        args = args,
        deps = all_deps,
        direct_defines = defines,
    )
    input_depsets.extend(transitive_inputs)
    input_depsets.append(depset(direct = srcs))

    if toolchain.supports_objc_interop:
        # Collect any additional inputs and flags needed to pull in Objective-C
        # dependencies.
        input_depsets.append(objc_compile_requirements(
            args = args,
            deps = all_deps,
        ))

    # Add toolchain copts, target copts, and command-line `--swiftcopt` flags,
    # in that order, so that more targeted usages can override more general
    # uses if needed.
    args.add_all(toolchain.swiftc_copts)
    args.add_all(copts)
    args.add_all(toolchain.command_line_copts)

    args.add_all(srcs)

    return depset(transitive = input_depsets)

def _toolchain_attrs(toolchain_attr_name = "_toolchain"):
    """Returns an attribute dictionary for toolchain users.

    The returned dictionary contains a key with the name specified by the
    argument `toolchain_attr_name` (which defaults to the value `"_toolchain"`),
    the value of which is a BUILD API `attr.label` that references the default
    Swift toolchain. Users who are authoring custom rules can add this dictionary
    to the attributes of their own rule in order to depend on the toolchain and
    access its `SwiftToolchainInfo` provider to pass it to other `swift_common`
    functions.

    There is a hierarchy to the attribute sets offered by the `swift_common` API:

    1. If you only need access to the toolchain for its tools and libraries but
       are not doing any compilation, use `toolchain_attrs`.
    2. If you need to invoke compilation actions but are not making the resulting
       object files into a static or shared library, use `compilation_attrs`.
    3. If you want to provide a rule interface that is suitable as a drop-in
       replacement for `swift_library`, use `library_rule_attrs`.

    Each of the attribute functions in the list above also contains the attributes
    from the earlier items in the list.

    Args:
      toolchain_attr_name: The name of the attribute that should be created that
          points to the toolchain. This defaults to `_toolchain`, which is
          sufficient for most rules; it is customizable for certain aspects where
          having an attribute with the same name but different values applied to
          a particular target causes a build crash.

    Returns:
      A new attribute dictionary that can be added to the attributes of a custom
      build rule to provide access to the Swift toolchain.
    """
    return {
        toolchain_attr_name: attr.label(
            default = Label("@build_bazel_rules_swift_local_config//:toolchain"),
            providers = [[SwiftToolchainInfo]],
        ),
    }

# The exported `swift_common` module, which defines the public API for directly
# invoking actions that compile Swift code from other rules.
swift_common = struct(
    cc_feature_configuration = _cc_feature_configuration,
    compilation_attrs = _compilation_attrs,
    compile_as_library = _compile_as_library,
    compile_as_objects = _compile_as_objects,
    configure_features = _configure_features,
    create_swift_info = _create_swift_info,
    derive_module_name = _derive_module_name,
    is_enabled = _is_enabled,
    library_rule_attrs = _library_rule_attrs,
    merge_swift_infos = _merge_swift_infos,
    run_toolchain_action = run_toolchain_action,
    run_toolchain_shell_action = run_toolchain_shell_action,
    run_toolchain_swift_action = run_toolchain_swift_action,
    swift_runtime_linkopts = _swift_runtime_linkopts,
    swiftc_command_line_and_inputs = _swiftc_command_line_and_inputs,
    toolchain_attrs = _toolchain_attrs,
)
