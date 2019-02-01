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
load(":debugging.bzl", "ensure_swiftmodule_is_embedded", "is_debugging")
load(":deps.bzl", "collect_link_libraries")
load(":derived_files.bzl", "derived_files")
load(
    ":features.bzl",
    "SWIFT_FEATURE_AUTOLINK_EXTRACT",
    "SWIFT_FEATURE_ENABLE_BATCH_MODE",
    "SWIFT_FEATURE_INDEX_WHILE_BUILDING",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_NO_GENERATED_HEADER",
    "SWIFT_FEATURE_NO_GENERATED_MODULE_MAP",
    "SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE",
    "SWIFT_FEATURE_USE_RESPONSE_FILES",
    "is_feature_enabled",
)
load(
    ":providers.bzl",
    "SwiftClangModuleInfo",
    "SwiftInfo",
    "SwiftToolchainInfo",
    "merge_swift_clang_module_infos",
)
load(":swift_cc_libs_aspect.bzl", "swift_cc_libs_excluding_directs_aspect")

# The compilation modes supported by Bazel.
_VALID_COMPILATION_MODES = [
    "dbg",
    "fastbuild",
    "opt",
]

# The Swift copts to pass for various sanitizer features.
_SANITIZER_FEATURE_FLAG_MAP = {
    "asan": ["-sanitize=address"],
    "tsan": ["-sanitize=thread"],
}

def _build_swift_info(
        additional_cc_libs = [],
        compile_options = [],
        deps = [],
        direct_additional_inputs = [],
        direct_defines = [],
        direct_libraries = [],
        direct_linkopts = [],
        direct_swiftdocs = [],
        direct_swiftmodules = [],
        module_name = None,
        swift_version = None):
    """Builds a `SwiftInfo` provider from direct outputs and dependencies.

    This function is recommended instead of directly creating a `SwiftInfo` provider because it
    encodes reasonable defaults for fields that some rules may not be interested in, and because it
    also automatically collects transitive values from dependencies.

    Args:
        additional_cc_libs: A list of additional `cc_library` dependencies whose libraries and
            linkopts need to be propagated by `SwiftInfo`.
        compile_options: A list of `Args` objects that contain the compilation options passed to
            `swiftc` to compile this target.
        deps: A list of dependencies of the target being built, which provide `SwiftInfo` providers.
        direct_additional_inputs: A list of additional input files passed into a library or binary
            target via the `swiftc_inputs` attribute.
        direct_defines: A list of defines that will be provided as `copts` of the target being
            built.
        direct_libraries: A list of `.a` files that are the direct outputs of the target being
            built.
        direct_linkopts: A list of linker flags that will be passed to the linker when the target
            being built is linked into a binary.
        direct_swiftdocs: A list of `.swiftdoc` files that are the direct outputs of the target
            being built.
        direct_swiftmodules: A list of `.swiftmodule` files that are the direct outputs of the
            target being built.
        module_name: A string containing the name of the Swift module, or `None` if the provider
            does not represent a compiled module (this happens, for example, with `proto_library`
            targets that act as "collectors" of other modules but have no sources of their own).
        swift_version: A string containing the value of the `-swift-version` flag used when
            compiling this target, or `None` if it was not set or is not relevant.

    Returns:
        A new `SwiftInfo` provider that propagates the direct and transitive libraries and modules
        for the target being built.
    """
    transitive_additional_inputs = []
    transitive_defines = []
    transitive_libraries = []
    transitive_linkopts = []
    transitive_swiftdocs = []
    transitive_swiftmodules = []

    # Note that we also collect the transitive libraries and linker flags from `cc_library`
    # dependencies and propagate them through the `SwiftInfo` provider; this is necessary because we
    # cannot construct our own `CcSkylarkApiProviders` from within Skylark, but only consume them.
    for dep in deps:
        transitive_libraries.extend(collect_link_libraries(dep))
        if SwiftInfo in dep:
            swift_info = dep[SwiftInfo]
            transitive_additional_inputs.append(swift_info.transitive_additional_inputs)
            transitive_defines.append(swift_info.transitive_defines)
            transitive_linkopts.append(swift_info.transitive_linkopts)
            transitive_swiftdocs.append(swift_info.transitive_swiftdocs)
            transitive_swiftmodules.append(swift_info.transitive_swiftmodules)
        if hasattr(dep, "cc"):
            transitive_linkopts.append(depset(direct = dep.cc.link_flags))

    for lib in additional_cc_libs:
        transitive_libraries.extend(collect_link_libraries(lib))
        transitive_linkopts.append(depset(direct = lib.cc.link_flags))

    return SwiftInfo(
        compile_options = compile_options,
        direct_defines = direct_defines,
        direct_libraries = direct_libraries,
        direct_linkopts = direct_linkopts,
        direct_swiftdocs = direct_swiftdocs,
        direct_swiftmodules = direct_swiftmodules,
        module_name = module_name,
        swift_version = swift_version,
        transitive_additional_inputs = depset(
            direct = direct_additional_inputs,
            transitive = transitive_additional_inputs,
        ),
        transitive_defines = depset(direct = direct_defines, transitive = transitive_defines),
        transitive_libraries = depset(
            direct = direct_libraries,
            transitive = transitive_libraries,
            order = "topological",
        ),
        transitive_linkopts = depset(direct = direct_linkopts, transitive = transitive_linkopts),
        transitive_swiftdocs = depset(direct = direct_swiftdocs, transitive = transitive_swiftdocs),
        transitive_swiftmodules = depset(
            direct = direct_swiftmodules,
            transitive = transitive_swiftmodules,
        ),
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
                allow_files = ["swift"],
                doc = """
A list of `.swift` source files that will be compiled into the library.
""",
            ),
            "cc_libs": attr.label_list(
                aspects = [swift_cc_libs_excluding_directs_aspect],
                doc = """
A list of `cc_library` targets that should be *merged* with the static library
or binary produced by this target.

Most normal Swift use cases do not need to make use of this attribute. It is
intended to support cases where C and Swift code *must* exist in the same
archive; for example, a Swift function annotated with `@_cdecl` which is then
referenced from C code in the same library.
""",
                providers = [["cc"]],
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

def _compilation_mode_copts(allow_testing, compilation_mode, wants_dsyms = False):
    """Returns `swiftc` compilation flags that match the given compilation mode.

    Args:
      allow_testing: If `True`, the `-enable-testing` flag will also be added to
          "dbg" and "fastbuild" builds. This argument is ignored for "opt" builds.
      compilation_mode: The compilation mode string ("fastbuild", "dbg", or
          "opt"). The build will fail if this is `None` or some other unrecognized
          mode.
      wants_dsyms: If `True`, the caller is requesting that the debug information
          be extracted into dSYM binaries. This affects the debug mode used during
          compilation.

    Returns:
      A list of strings containing copts that should be passed to Swift.
    """
    if compilation_mode not in _VALID_COMPILATION_MODES:
        fail("'compilation_mode' must be one of: {}".format(
            _VALID_COMPILATION_MODES,
        ))

    # The combinations of flags used here mirror the descriptions of these
    # compilation modes given in the Bazel documentation.
    flags = []
    if compilation_mode == "opt":
        flags += ["-O", "-DNDEBUG"]
    elif compilation_mode in ("dbg", "fastbuild"):
        if allow_testing:
            flags.append("-enable-testing")

        # The Swift compiler only serializes debugging options in narrow
        # circumstances (for example, for application binaries). Since we almost
        # exclusively just compile to object files directly, we need to manually
        # pass the following frontend option to ensure that LLDB has the necessary
        # import search paths to find definitions during debugging.
        flags += ["-Onone", "-DDEBUG", "-Xfrontend", "-serialize-debugging-options"]

    # The combination of dsymutil and -gline-tables-only appears to cause
    # spurious warnings about symbols in the debug map, so if the caller is
    # requesting dSYMs, then force `-g` regardless of compilation mode.
    if compilation_mode == "dbg" or wants_dsyms:
        flags.append("-g")
    elif compilation_mode == "fastbuild":
        flags.append("-gline-tables-only")

    return flags

def _coverage_copts(configuration):
    """Returns `swiftc` compilation flags for code converage if enabled.

    Args:
      configuration: The default configuration from which certain compilation
          options are determined, such as whether coverage is enabled. This object
          should be one obtained from a rule's `ctx.configuraton` field. If
          omitted, no default-configuration-specific options will be used.

    Returns:
      A list of compiler flags that enable code coverage if requested.
    """
    if configuration and configuration.coverage_enabled:
        return ["-profile-generate", "-profile-coverage-mapping"]
    return []

def _sanitizer_copts(feature_configuration):
    """Returns `swiftc` compilation flags for any requested sanitizer features.

    Args:
      feature_configuration: The feature configuration.

    Returns:
      A list of compiler flags that enable the requested sanitizers for a Swift
      compilation action.
    """
    copts = []
    for (feature, flags) in _SANITIZER_FEATURE_FLAG_MAP.items():
        if is_feature_enabled(feature, feature_configuration):
            copts.extend(flags)
    return copts

def _global_module_cache_path(genfiles_dir):
    """Returns the path of the global Clang module cache.

    Args:
      genfiles_dir: The Bazel `*-genfiles` directory root where the module
          cache directory is created by Objective-C compilation actions. Note
          that this is non-hermetic.

    Returns:
      The path to the global Clang module path.
    """

    # This path matches the one passed to Clang in Bazel's
    # java/com/google/devtools/build/lib/rules/objc/CompilationSupport.java.
    return paths.join(genfiles_dir.path, "_objc_module_cache")

def _is_wmo(copts, swift_fragment):
    """Returns a value indicating whether a compilation will use whole module optimization.

    Args:
      copts: A list of compiler flags to scan for WMO usage.
      swift_fragment: The `swift` configuration fragment from Bazel.

    Returns:
      True if WMO is enabled in the given list of flags.
    """
    all_copts = copts + swift_fragment.copts()
    return ("-wmo" in all_copts or
            "-whole-module-optimization" in all_copts or
            "-force-single-frontend-invocation" in all_copts)

def _compile_as_objects(
        actions,
        arguments,
        compilation_mode,
        module_name,
        srcs,
        swift_fragment,
        target_name,
        toolchain,
        additional_input_depsets = [],
        additional_outputs = [],
        allow_testing = True,
        configuration = None,
        copts = [],
        defines = [],
        deps = [],
        feature_configuration = None,
        genfiles_dir = None,
        objc_fragment = None):
    """Compiles Swift source files into object files (and optionally a module).

    Args:
      actions: The context's `actions` object.
      arguments: A list of `Args` objects that provide additional arguments to the
          compiler, not including the `copts` list.
      compilation_mode: The Bazel compilation mode; must be `dbg`, `fastbuild`, or
          `opt`.
      module_name: The name of the Swift module being compiled. This must be
          present and valid; use `swift_common.derive_module_name` to generate a
          default from the target's label if needed.
      srcs: The Swift source files to compile.
      swift_fragment: The `swift` configuration fragment from Bazel.
      target_name: The name of the target for which the code is being compiled,
          which is used to determine unique file paths for the outputs.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      additional_input_depsets: A list of `depset`s of `File`s representing
          additional input files that need to be passed to the Swift compile
          action because they are referenced by compiler flags.
      additional_outputs: A list of `File`s representing files that should be
          treated as additional outputs of the compilation action.
      allow_testing: Indicates whether the module should be compiled with testing
          enabled (only when the compilation mode is `fastbuild` or `dbg`).
      configuration: The default configuration from which certain compilation
          options are determined, such as whether coverage is enabled. This object
          should be one obtained from a rule's `ctx.configuraton` field. If
          omitted, no default-configuration-specific options will be used.
      copts: A list (**not** an `Args` object) of compiler flags that apply to the
          target being built. These flags, along with those from Bazel's Swift
          configuration fragment (i.e., `--swiftcopt` command line flags) are
          scanned to determine whether whole module optimization is being
          requested, which affects the nature of the output files.
      defines: Symbols that should be defined by passing `-D` to the compiler.
      deps: Dependencies of the target being compiled. These targets must
          propagate one of the following providers: `SwiftClangModuleInfo`,
          `SwiftInfo`, `"cc"`, or `apple_common.Objc`.
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`. If omitted, a default feature
          configuration will be used, but this argument will be required in the
          future.
      genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its path
          is added to ClangImporter's header search paths for compatibility with
          Bazel's C++ and Objective-C rules which support inclusions of generated
          headers from that location.
      objc_fragment: The `objc` configuration fragment from Bazel. This must be
          provided if the toolchain supports Objective-C interop; if it does not,
          then this argument may be omitted.

    Returns:
      A `struct` containing the following fields:

      * `compile_inputs`: A `depset` of `File`s representing the full collection
        of files that were used as inputs to the compile action. This can be used
        if those files need to also be made available to subsequent link actions.
      * `compile_options`: A list of `Args` objects containing the complete set
        of command line flags that were passed to the compiler. This is mainly
        exposed for aspects to inspect so that IDEs can integrate with SourceKit.
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

    # TODO(b/112900284): Make this a required argument.
    if not feature_configuration:
        feature_configuration = _configure_features(toolchain)

    # Force threaded mode for WMO builds, using the same number of cores that is
    # on a Mac Pro for historical reasons.
    # TODO(b/32571265): Generalize this based on platform and core count when an
    # API to obtain this is available.
    if _is_wmo(copts, swift_fragment):
        # We intentionally don't use `+=` or `extend` here to ensure that a
        # copy is made instead of extending the original.
        copts = copts + ["-num-threads", "12"]

    compile_reqs = declare_compile_outputs(
        actions = actions,
        copts = copts + swift_fragment.copts(),
        srcs = srcs,
        target_name = target_name,
        index_while_building = is_feature_enabled(
            SWIFT_FEATURE_INDEX_WHILE_BUILDING,
            feature_configuration,
        ),
    )
    output_objects = compile_reqs.output_objects

    out_module = derived_files.swiftmodule(actions, module_name = module_name)
    out_doc = derived_files.swiftdoc(actions, module_name = module_name)

    wrapper_args = actions.args()
    if is_feature_enabled(SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE, feature_configuration):
        # If genfiles_dir is not provided, then we don't pass any special flags to the compiler,
        # letting it decide where the cache should live. This is usually somewhere in the system
        # temporary directory.
        if genfiles_dir:
            wrapper_args.add("-module-cache-path", _global_module_cache_path(genfiles_dir))
    else:
        wrapper_args.add("-Xwrapped-swift=-ephemeral-module-cache")

    compile_args = actions.args()
    if is_feature_enabled(SWIFT_FEATURE_USE_RESPONSE_FILES, feature_configuration):
        compile_args.use_param_file("@%s", use_always = True)

    compile_args.add("-emit-object")
    compile_args.add_all(compile_reqs.args)
    compile_args.add("-emit-module-path")
    compile_args.add(out_module)

    basic_inputs = _swiftc_command_line_and_inputs(
        args = compile_args,
        compilation_mode = compilation_mode,
        module_name = module_name,
        srcs = srcs,
        swift_fragment = swift_fragment,
        toolchain = toolchain,
        additional_input_depsets = additional_input_depsets,
        allow_testing = allow_testing,
        configuration = configuration,
        copts = copts,
        defines = defines,
        deps = deps,
        feature_configuration = feature_configuration,
        genfiles_dir = genfiles_dir,
        objc_fragment = objc_fragment,
    )

    all_inputs = depset(
        transitive = [basic_inputs, depset(direct = compile_reqs.compile_inputs)],
    )
    compile_outputs = ([out_module, out_doc] + output_objects +
                       compile_reqs.other_outputs) + additional_outputs

    run_toolchain_swift_action(
        actions = actions,
        arguments = [wrapper_args, compile_args] + arguments,
        inputs = all_inputs,
        mnemonic = "SwiftCompile",
        outputs = compile_outputs,
        progress_message = "Compiling Swift module {}".format(module_name),
        swift_tool = "swiftc",
        toolchain = toolchain,
    )

    linker_flags = []
    linker_inputs = []

    # Ensure that the .swiftmodule file is embedded in the final library or binary
    # for debugging purposes.
    if is_debugging(compilation_mode):
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
    if is_feature_enabled(SWIFT_FEATURE_AUTOLINK_EXTRACT, feature_configuration):
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
        compile_options = ([compile_args] + arguments),
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
        compilation_mode,
        label,
        module_name,
        srcs,
        swift_fragment,
        toolchain,
        additional_inputs = [],
        allow_testing = True,
        alwayslink = False,
        cc_libs = [],
        configuration = None,
        copts = [],
        defines = [],
        deps = [],
        feature_configuration = None,
        genfiles_dir = None,
        library_name = None,
        linkopts = [],
        objc_fragment = None):
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
      compilation_mode: The Bazel compilation mode; must be `dbg`, `fastbuild`, or
          `opt`.
      label: The target label for which the code is being compiled, which is used
          to determine unique file paths for the outputs.
      module_name: The name of the Swift module being compiled. This must be
          present and valid; use `swift_common.derive_module_name` to generate a
          default from the target's label if needed.
      srcs: The Swift source files to compile.
      swift_fragment: The `swift` configuration fragment from Bazel.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      additional_inputs: A list of `File`s representing additional inputs that
          need to be passed to the Swift compile action because they are
          referenced in compiler flags.
      allow_testing: Indicates whether the module should be compiled with testing
          enabled (only when the compilation mode is `fastbuild` or `dbg`).
      alwayslink: Indicates whether the object files in the library should always
          be always be linked into any binaries that depend on it, even if some
          contain no symbols referenced by the binary.
      cc_libs: Additional `cc_library` targets whose static libraries should be
          merged into the resulting archive.
      configuration: The default configuration from which certain compilation
          options are determined, such as whether coverage is enabled. This object
          should be one obtained from a rule's `ctx.configuraton` field. If
          omitted, no default-configuration-specific options will be used.
      copts: Additional flags that should be passed to `swiftc`.
      defines: Symbols that should be defined by passing `-D` to the compiler.
      deps: Dependencies of the target being compiled. These targets must
          propagate one of the following providers: `SwiftClangModuleInfo`,
          `SwiftInfo`, `"cc"`, or `apple_common.Objc`.
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`. If omitted, a default feature
          configuration will be used, but this argument will be required in the
          future.
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
      objc_fragment: The `objc` configuration fragment from Bazel. This must be
          provided if the toolchain supports Objective-C interop; if it does not,
          then this argument may be omitted.

    Returns:
      A `struct` containing the following fields:

      * `compile_inputs`: A `depset` of `File`s representing the full collection
        of files that were used as inputs to the compile action. This can be used
        if those files need to also be made available to subsequent link actions.
      * `compile_options`: A list of `Args` objects containing the complete set
        of command line flags that were passed to the compiler. This is mainly
        exposed for aspects to inspect so that IDEs can integrate with SourceKit.
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

    # TODO(b/112900284): Make this a required argument.
    if not feature_configuration:
        feature_configuration = _configure_features(toolchain)

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
    if is_feature_enabled(SWIFT_FEATURE_USE_RESPONSE_FILES, feature_configuration):
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

    generates_header = not is_feature_enabled(
        SWIFT_FEATURE_NO_GENERATED_HEADER,
        feature_configuration,
    )
    if generates_header and toolchain.supports_objc_interop and objc_fragment:
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
        if not is_feature_enabled(SWIFT_FEATURE_NO_GENERATED_MODULE_MAP, feature_configuration):
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
        compilation_mode = compilation_mode,
        copts = copts,
        defines = defines,
        feature_configuration = feature_configuration,
        module_name = module_name,
        srcs = srcs,
        swift_fragment = swift_fragment,
        target_name = label.name,
        toolchain = toolchain,
        additional_input_depsets = compile_input_depsets,
        additional_outputs = additional_outputs,
        allow_testing = allow_testing,
        configuration = configuration,
        deps = deps,
        genfiles_dir = genfiles_dir,
        objc_fragment = objc_fragment,
    )

    # Create an archive that contains the compiled .o files. If we have any
    # cc_libs that should also be included, merge those into the archive as well.
    cc_lib_files = []
    for target in cc_libs:
        cc_lib_files.extend([f for f in target.files.to_list() if f.basename.endswith(".a")])

    if toolchain.system_name == "darwin":
        ar_executable = None
    else:
        ar_executable = toolchain.cc_toolchain_info.ar_executable

    register_static_archive_action(
        actions = actions,
        ar_executable = ar_executable,
        libraries = cc_lib_files,
        mnemonic = "SwiftArchive",
        objects = compile_results.output_objects,
        output = out_archive,
        progress_message = "Linking {}".format(out_archive.short_path),
        toolchain = toolchain,
    )

    providers = [
        _build_swift_info(
            additional_cc_libs = cc_libs,
            compile_options = compile_results.compile_options,
            deps = all_deps,
            direct_additional_inputs = (
                additional_inputs + compile_results.linker_inputs
            ),
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
    if toolchain.supports_objc_interop and objc_fragment:
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
        compile_options = compile_results.compile_options,
        output_archive = out_archive,
        output_doc = compile_results.output_doc,
        output_groups = compile_results.output_groups,
        output_header = objc_header,
        output_module = compile_results.output_module,
        providers = providers,
    )

def _configure_features(toolchain, requested_features = [], unsupported_features = []):
    """Creates a feature configuration that should be passed to other Swift build APIs.

    The feature configuration is a value that encapsulates the list of features that have been
    explicitly enabled or disabled by the user as well as those enabled or disabled by the
    toolchain. The other Swift build APIs query this value to determine which features should be
    used during the build.

    Users should treat the return value of this function as an opaque value and should only operate
    on it using other API functions, like `swift_common.get_{enabled,disabled}_features`. Its
    internal representation is an implementation detail and subject to change.

    Args:
        toolchain: The `SwiftToolchainInfo` provider of the toolchain being used to build.
        requested_features: The list of user-enabled features _only_. This is typically obtained
            using the `ctx.features` field in a rule implementation function. It should _not_ be
            merged with any features from the toolchain; the feature configuration manages those.
        unsupported_features: The list of user-disabled features _only_. This is typically obtained
            using the `ctx.disabled_features` field in a rule implementation function. It should
            _not_ be merged with any disabled features from the toolchain; the feature configuration
            manages those.

    Returns:
        An opaque value that should be passed as the `feature_configuration` argument of other
        `swift_common` API calls.
    """
    return struct(
        requested_features = requested_features,
        toolchain = toolchain,
        unsupported_features = unsupported_features,
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
          type(args[0]) == type("") and
          type(args[1]) == type("")):
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

def _get_disabled_features(feature_configuration):
    """Returns the list of disabled features in the feature configuration.

    Args:
        feature_configuration: The feature configuration.

    Returns:
        A list containing the names of features that are disabled in the given feature
        configuration.
    """

    # The full set of disabled features includes the ones that the user explicitly asked to be
    # disabled in a target/package...
    disabled_features_set = sets.make(feature_configuration.unsupported_features)

    # ...plus the ones that the toolchain does not support...
    disabled_features_set = sets.union(
        disabled_features_set,
        sets.make(feature_configuration.toolchain.unsupported_features),
    )

    # ...unless the user has asked for any toolchain-unsupported features to be explicitly enabled
    # on a target/package.
    disabled_features_set = sets.difference(
        disabled_features_set,
        sets.make(feature_configuration.requested_features),
    )
    return sets.to_list(disabled_features_set)

def _get_enabled_features(feature_configuration):
    """Returns the list of enabled features in the feature configuration.

    Args:
        feature_configuration: The feature configuration.

    Returns:
        A list containing the names of features that are enabled in the given feature configuration.
    """

    # The full set of enabled features includes the ones that the user explicitly asked to be
    # enabled in a target/package...
    enabled_features_set = sets.make(feature_configuration.requested_features)

    # ...plus the ones that the toolchain supports...
    enabled_features_set = sets.union(
        enabled_features_set,
        sets.make(feature_configuration.toolchain.requested_features),
    )

    # ...unless the user has asked for any toolchain-supported features to be explicitly disnabled
    # on a target/package.
    enabled_features_set = sets.difference(
        enabled_features_set,
        sets.make(feature_configuration.unsupported_features),
    )
    return sets.to_list(enabled_features_set)

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
            "module_link_name": attr.string(
                doc = """
The name of the library that should be linked to targets that depend on this
library. Supports auto-linking.
""",
                mandatory = False,
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

def _merge_swift_info_providers(targets):
    """Merges the transitive `SwiftInfo` of the given targets into a new provider.

    This function should be used when it is necessary to merge `SwiftInfo`
    providers outside of a compile action (which does it automatically).

    Args:
      targets: A sequence of targets that may propagate `SwiftInfo` providers.
          Those that do not are ignored.

    Returns:
      A new `SwiftInfo` provider that contains the transitive information from all
      the targets.
    """
    transitive_additional_inputs = []
    transitive_defines = []
    transitive_libraries = []
    transitive_linkopts = []
    transitive_swiftdocs = []
    transitive_swiftmodules = []

    for target in targets:
        if SwiftInfo in target:
            p = target[SwiftInfo]
            transitive_additional_inputs.append(p.transitive_additional_inputs)
            transitive_defines.append(p.transitive_defines)
            transitive_libraries.append(p.transitive_libraries)
            transitive_linkopts.append(p.transitive_linkopts)
            transitive_swiftdocs.append(p.transitive_swiftdocs)
            transitive_swiftmodules.append(p.transitive_swiftmodules)

    return SwiftInfo(
        compile_options = [],
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
        compilation_mode,
        module_name,
        srcs,
        swift_fragment,
        toolchain,
        additional_input_depsets = [],
        allow_testing = True,
        configuration = None,
        copts = [],
        defines = [],
        deps = [],
        feature_configuration = None,
        genfiles_dir = None,
        objc_fragment = None):
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
      compilation_mode: The Bazel compilation mode; must be `dbg`, `fastbuild`, or
          `opt`.
      module_name: The name of the Swift module being compiled. This must be
          present and valid; use `swift_common.derive_module_name` to generate a
          default from the target's label if needed.
      srcs: The Swift source files to compile.
      swift_fragment: The `swift` configuration fragment from Bazel.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      additional_input_depsets: A list of `depset`s of `File`s representing
          additional input files that need to be passed to the Swift compile
          action because they are referenced by compiler flags.
      allow_testing: Indicates whether the module should be compiled with testing
          enabled (only when the compilation mode is `fastbuild` or `dbg`).
      configuration: The default configuration from which certain compilation
          options are determined, such as whether coverage is enabled. This object
          should be one obtained from a rule's `ctx.configuraton` field. If
          omitted, no default-configuration-specific options will be used.
      copts: A list (**not** an `Args` object) of compiler flags that apply to the
          target being built. These flags, along with those from Bazel's Swift
          configuration fragment (i.e., `--swiftcopt` command line flags) are
          scanned to determine whether whole module optimization is being
          requested, which affects the nature of the output files.
      defines: Symbols that should be defined by passing `-D` to the compiler.
      deps: Dependencies of the target being compiled. These targets must
          propagate one of the following providers: `SwiftClangModuleInfo`,
          `SwiftInfo`, `"cc"`, or `apple_common.Objc`.
      feature_configuration: A feature configuration obtained from
          `swift_common.configure_features`. If omitted, a default feature
          configuration will be used, but this argument will be required in the
          future.
      genfiles_dir: The Bazel `*-genfiles` directory root. If provided, its path
          is added to ClangImporter's header search paths for compatibility with
          Bazel's C++ and Objective-C rules which support inclusions of generated
          headers from that location.
      objc_fragment: The `objc` configuration fragment from Bazel. This must be
          provided if the toolchain supports Objective-C interop; if it does not,
          then this argument may be omitted.

    Returns:
      A `depset` containing the full set of files that need to be passed as inputs
      of the Bazel action that spawns a tool with the computed command line (i.e.,
      any source files, referenced module maps and headers, and so forth.)
    """

    # TODO(b/112900284): Make this a required argument.
    if not feature_configuration:
        feature_configuration = _configure_features(toolchain)

    all_deps = deps + toolchain.implicit_deps

    args.add("-module-name")
    args.add(module_name)

    args.add_all(_compilation_mode_copts(
        allow_testing = allow_testing,
        compilation_mode = compilation_mode,
        wants_dsyms = objc_fragment.generate_dsym if objc_fragment else False,
    ))
    args.add_all(_coverage_copts(configuration = configuration))
    args.add_all(_sanitizer_copts(feature_configuration = feature_configuration))
    args.add_all(["-Xfrontend", "-color-diagnostics"])

    if is_feature_enabled(SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD, feature_configuration):
        args.add_all(collections.before_each(
            "-Xcc",
            ["-Xclang", "-fmodule-map-file-home-is-cwd"],
        ))

    # Do not enable batch mode if the user requested WMO; this silences an "ignoring
    # '-enable-batch-mode' because '-whole-module-optimization' was also specified" warning.
    if (not _is_wmo(copts, swift_fragment) and
        is_feature_enabled(SWIFT_FEATURE_ENABLE_BATCH_MODE, feature_configuration)):
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

    if toolchain.supports_objc_interop and objc_fragment:
        # Collect any additional inputs and flags needed to pull in Objective-C
        # dependencies.
        input_depsets.append(objc_compile_requirements(
            args = args,
            deps = all_deps,
            objc_fragment = objc_fragment,
        ))

    # Add toolchain copts, target copts, and command-line `--swiftcopt` flags,
    # in that order, so that more targeted usages can override more general
    # uses if needed.
    args.add_all(toolchain.swiftc_copts)
    args.add_all(copts)
    args.add_all(swift_fragment.copts())

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
    build_swift_info = _build_swift_info,
    compilation_attrs = _compilation_attrs,
    compilation_mode_copts = _compilation_mode_copts,
    compile_as_library = _compile_as_library,
    compile_as_objects = _compile_as_objects,
    configure_features = _configure_features,
    derive_module_name = _derive_module_name,
    get_disabled_features = _get_disabled_features,
    get_enabled_features = _get_enabled_features,
    library_rule_attrs = _library_rule_attrs,
    merge_swift_info_providers = _merge_swift_info_providers,
    run_toolchain_action = run_toolchain_action,
    run_toolchain_shell_action = run_toolchain_shell_action,
    run_toolchain_swift_action = run_toolchain_swift_action,
    swift_runtime_linkopts = _swift_runtime_linkopts,
    swiftc_command_line_and_inputs = _swiftc_command_line_and_inputs,
    toolchain_attrs = _toolchain_attrs,
)
