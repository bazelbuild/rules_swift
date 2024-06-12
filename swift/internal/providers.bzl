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

"""Defines Starlark providers that propagated by the Swift BUILD rules."""

SwiftCompilerPluginInfo = provider(
    doc = "Information about compiler plugins, like macros.",
    fields = {
        "cc_info": """\
A `CcInfo` provider containing the `swift_compiler_plugin`'s code compiled as a
static library, which is suitable for linking into a `swift_test` so that unit
tests can be written against it.
""",
        "executable": "A `File` representing the plugin's binary executable.",
        "module_names": """\
A `depset` of strings denoting the names of the Swift modules that provide
plugin types looked up by the compiler. This currently contains a single
element, the name of the module created by the `swift_compiler_plugin` target.
""",
        "swift_info": """\
A `SwiftInfo` provider representing the Swift module created by the
`swift_compiler_plugin` target. This is used specifically by `swift_test` to
allow test code to depend on the plugin's module without making it possible for
arbitrary libraries/binaries to depend on a plugin.
""",
    },
)

SwiftFeatureAllowlistInfo = provider(
    doc = """\
Describes a set of features and the packages that are allowed to request or
disable them.

This provider is an internal implementation detail of the rules; users should
not rely on it or assume that its structure is stable.
""",
    fields = {
        "allowlist_label": """\
A string containing the label of the `swift_feature_allowlist` target that
created this provider.
""",
        "managed_features": """\
A list of strings representing feature names or their negations that packages in
the `packages` list are allowed to explicitly request or disable.
""",
        "package_specs": """\
A list of `struct` values representing package specifications that indicate
which packages (possibly recursive) can request or disable a feature managed by
the allowlist.
""",
    },
)

SwiftInfo = provider(
    doc = """\
Contains information about the compiled artifacts of a Swift module.

This provider contains a large number of fields and many custom rules may not
need to set all of them. Instead of constructing a `SwiftInfo` provider
directly, consider using the `swift_common.create_swift_info` function, which
has reasonable defaults for any fields not explicitly set.
""",
    fields = {
        "direct_modules": """\
`List` of values returned from `swift_common.create_module`. The modules (both
Swift and C/Objective-C) emitted by the library that propagated this provider.
""",
        "transitive_modules": """\
`Depset` of values returned from `swift_common.create_module`. The transitive
modules (both Swift and C/Objective-C) emitted by the library that propagated
this provider and all of its dependencies.
""",
    },
)

SwiftPackageConfigurationInfo = provider(
    doc = """\
Describes a compiler configuration that is applied by default to targets in a
specific set of packages.

This provider is an internal implementation detail of the rules; users should
not rely on it or assume that its structure is stable.
""",
    fields = {
        "disabled_features": """\
`List` of strings. Features that will be disabled by default on targets in the
packages listed in this package configuration.
""",
        "enabled_features": """\
`List` of strings. Features that will be enabled by default on targets in the
packages listed in this package configuration.
""",
        "package_specs": """\
A list of `struct` values representing package specifications that indicate
the set of packages (possibly recursive) to which this configuration is applied.
""",
    },
)

SwiftProtoCompilerInfo = provider(
    doc = """\
Provides information needed to generate Swift code from `ProtoInfo` providers
""",
    fields = {
        "bundled_proto_paths": """\
List of proto paths for which to skip generation because they're built into the modules
imported by the generated Swift proto code, e.g., SwiftProtobuf.
""",
        "compile": """\
A function which compiles Swift source files from `ProtoInfo` providers.

Args:
    label: The label of the target for which the Swift files are being generated.
    actions: The actions object used to declare the files to be generated and the actions that generate them.
    swift_proto_compiler_info: This `SwiftProtoCompilerInfo` provider.
    additional_compiler_info: Additional information passed from the target target to the compiler.
    proto_infos: The list of `ProtoInfo` providers to compile.
    module_mappings: The module_mappings field of the `SwiftProtoInfo` for the target.

Returns:
    A list of .swift Files generated by the compiler.
""",
        "compiler_deps": """\
List of targets providing SwiftInfo and CcInfo.
These are added as dependencies to the swift compile action of the swift_proto_library.
Typically these are proto runtime libraries.

Well Known Types should be added as dependencies of the swift_proto_library
targets as needed to avoid compiling them unnecessarily.
""",
        "internal": """\
Opaque struct passing information from the compiler target to the compile function.
""",
    },
)

SwiftProtoInfo = provider(
    doc = "Propagates Swift-specific information about a `proto_library`.",
    fields = {
        "module_name": """\
The name of the Swift module compiled from the `swift_proto_library` which produced this provider.
""",
        "module_mappings": """\
`list` of `struct`s. Each struct contains `module_name` and
`proto_file_paths` fields that denote the transitive mappings from `.proto`
files to Swift modules. This allows messages that reference messages in other
libraries to import those modules in generated code.
""",
        "direct_pbswift_files": """\
`list` of `File`s. The Swift source files (e.g. `.pb.swift`) generated from the
`ProtoInfo` providers of the direct proto dependencies of the `swift_proto_library` target.
""",
        "pbswift_files": """\
`depset` of `File`s. The Swift source files (e.g. `.pb.swift`) generated from the
`ProtoInfo` providers of the direct and transitive transitive proto dependencies
of the `swift_proto_library` target.
""",
    },
)

SwiftSymbolGraphInfo = provider(
    doc = "Propagates extracted symbol graph files from Swift modules.",
    fields = {
        "direct_symbol_graphs": """\
`List` of `struct`s representing the symbol graphs extracted from the target
that propagated this provider. This list will be empty if propagated by a
non-Swift target (although its `transitive_symbol_graphs` may be non-empty if it
has Swift dependencies).

Each `struct` has the following fields:

*   `module_name`: A string denoting the name of the Swift module.
*   `symbol_graph_dir`: A directory-type `File` containing one or more
    `.symbols.json` files representing the symbol graph(s) for the module.
""",
        "transitive_symbol_graphs": """\
`Depset` of `struct`s representing the symbol graphs extracted from the target
that propagated this provider and all of its Swift dependencies. Each `struct`
has the same fields as documented in `direct_symbol_graphs`.
""",
    },
)

SwiftToolchainInfo = provider(
    doc = """
Propagates information about a Swift toolchain to compilation and linking rules
that use the toolchain.
""",
    fields = {
        "action_configs": """\
This field is an internal implementation detail of the build rules.
""",
        "cc_toolchain_info": """\
The `cc_common.CcToolchainInfo` provider from the Bazel C++ toolchain that this
Swift toolchain depends on.
""",
        "clang_implicit_deps_providers": """\
A `struct` with the following fields, which represent providers from targets
that should be added as implicit dependencies of any precompiled explicit
C/Objective-C modules:

*   `cc_infos`: A list of `CcInfo` providers from targets specified as the
    toolchain's implicit dependencies.
*   `objc_infos`: A list of `apple_common.Objc` providers from targets specified
    as the toolchain's implicit dependencies.
*   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the
    toolchain's implicit dependencies.

For ease of use, this field is never `None`; it will always be a valid `struct`
containing the fields described above, even if those lists are empty.
""",
        "const_protocols_to_gather": """\
`File`. A JSON file specifying a list of protocols for extraction of
conformances' const values.
""",
        "developer_dirs": """
A list of `structs` containing the following fields:\
*   `developer_path_label`: A `string` representing the type of developer path.
*   `path`: A `string` representing the path to the developer framework.
""",
        "entry_point_linkopts_provider": """\
A function that returns flags that should be passed to the linker to control the
name of the entry point of a linked binary for rules that customize their entry
point.
This function must take the following keyword arguments:
*   `entry_point_name`: The name of the entry point function, as was passed to
    the Swift compiler using the `-entry-point-function-name` flag.
It must return a `struct` with the following fields:
*   `linkopts`: A list of strings that will be passed as additional linker flags
    when linking a binary with a custom entry point.
""",
        "feature_allowlists": """\
A list of `SwiftFeatureAllowlistInfo` providers that allow or prohibit packages
from requesting or disabling features.
""",
        "generated_header_module_implicit_deps_providers": """\
A `struct` with the following fields, which are providers from targets that
should be treated as compile-time inputs to actions that precompile the explicit
module for the generated Objective-C header of a Swift module:

*   `cc_infos`: A list of `CcInfo` providers from targets specified as the
    toolchain's implicit dependencies.
*   `objc_infos`: A list of `apple_common.Objc` providers from targets specified
    as the toolchain's implicit dependencies.
*   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the
    toolchain's implicit dependencies.

This is used to provide modular dependencies for the fixed inclusions (Darwin,
Foundation) that are unconditionally emitted in those files.

For ease of use, this field is never `None`; it will always be a valid `struct`
containing the fields described above, even if those lists are empty.
""",
        "implicit_deps_providers": """\
A `struct` with the following fields, which represent providers from targets
that should be added as implicit dependencies of any Swift compilation or
linking target (but not to precompiled explicit C/Objective-C modules):

*   `cc_infos`: A list of `CcInfo` providers from targets specified as the
    toolchain's implicit dependencies.
*   `objc_infos`: A list of `apple_common.Objc` providers from targets specified
    as the toolchain's implicit dependencies.
*   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the
    toolchain's implicit dependencies.

For ease of use, this field is never `None`; it will always be a valid `struct`
containing the fields described above, even if those lists are empty.
""",
        "package_configurations": """\
A list of `SwiftPackageConfigurationInfo` providers that specify additional
compilation configuration options that are applied to targets on a per-package
basis.
""",
        "requested_features": """\
`List` of `string`s. Features that should be implicitly enabled by default for
targets built using this toolchain, unless overridden by the user by listing
their negation in the `features` attribute of a target/package or in the
`--features` command line flag.

These features determine various compilation and debugging behaviors of the
Swift build rules, and they are also passed to the C++ APIs used when linking
(so features defined in CROSSTOOL may be used here).
""",
        "root_dir": """\
`String`. The workspace-relative root directory of the toolchain.
""",
        "swift_worker": """\
`File`. The executable representing the worker executable used to invoke the
compiler and other Swift tools (for both incremental and non-incremental
compiles).
""",
        "test_configuration": """\
`Struct` containing two fields:

*   `env`: A `dict` of environment variables to be set when running tests
    that were built with this toolchain.

*   `execution_requirements`: A `dict` of execution requirements for tests
    that were built with this toolchain.

This is used, for example, with Xcode-based toolchains to ensure that the
`xctest` helper and coverage tools are found in the correct developer
directory when running tests.
""",
        "tool_configs": """\
This field is an internal implementation detail of the build rules.
""",
        "unsupported_features": """\
`List` of `string`s. Features that should be implicitly disabled by default for
targets built using this toolchain, unless overridden by the user by listing
them in the `features` attribute of a target/package or in the `--features`
command line flag.

These features determine various compilation and debugging behaviors of the
Swift build rules, and they are also passed to the C++ APIs used when linking
(so features defined in CROSSTOOL may be used here).
""",
    },
)

SwiftUsageInfo = provider(
    doc = """\
A provider that indicates that Swift was used by a target or any target that it
depends on.
""",
    fields = {},
)

def create_module(
        *,
        name,
        clang = None,
        const_gather_protocols = [],
        compilation_context = None,
        is_system = False,
        swift = None):
    """Creates a value containing Clang/Swift module artifacts of a dependency.

    It is possible for both `clang` and `swift` to be present; this is the case
    for Swift modules that generate an Objective-C header, where the Swift
    module artifacts are propagated in the `swift` context and the generated
    header and module map are propagated in the `clang` context.

    Though rare, it is also permitted for both the `clang` and `swift` arguments
    to be `None`. One example of how this can be used is to model system
    dependencies (like Apple SDK frameworks) that are implicitly available as
    part of a non-hermetic SDK (Xcode) but do not propagate any artifacts of
    their own. This would only apply in a build using implicit modules, however;
    when using explicit modules, one would propagate the module artifacts
    explicitly. But allowing for the empty case keeps the build graph consistent
    if switching between the two modes is necessary, since it will not change
    the set of transitive module names that are propagated by dependencies
    (which other build rules may want to depend on for their own analysis).

    Args:
        name: The name of the module.
        clang: A value returned by `swift_common.create_clang_module` that
            contains artifacts related to Clang modules, such as a module map or
            precompiled module. This may be `None` if the module is a pure Swift
            module with no generated Objective-C interface.
        const_gather_protocols: A list of protocol names from which constant
            values should be extracted from source code that takes this module
            as a *direct* dependency.
        compilation_context: A value returned from
            `swift_common.create_compilation_context` that contains the
            context needed to compile the module being built. This may be `None`
            if the module wasn't compiled from sources.
        is_system: Indicates whether the module is a system module. The default
            value is `False`. System modules differ slightly from non-system
            modules in the way that they are passed to the compiler. For
            example, non-system modules have their Clang module maps passed to
            the compiler in both implicit and explicit module builds. System
            modules, on the other hand, do not have their module maps passed to
            the compiler in implicit module builds because there is currently no
            way to indicate that modules declared in a file passed via
            `-fmodule-map-file` should be treated as system modules even if they
            aren't declared with the `[system]` attribute, and some system
            modules may not build cleanly with respect to warnings otherwise.
            Therefore, it is assumed that any module with `is_system == True`
            must be able to be found using import search paths in order for
            implicit module builds to succeed.
        swift: A value returned by `swift_common.create_swift_module` that
            contains artifacts related to Swift modules, such as the
            `.swiftmodule`, `.swiftdoc`, and/or `.swiftinterface` files emitted
            by the compiler. This may be `None` if the module is a pure
            C/Objective-C module.

    Returns:
        A `struct` containing the `name`, `clang`, `is_system`, and `swift`
        fields provided as arguments.
    """
    return struct(
        clang = clang,
        const_gather_protocols = tuple(const_gather_protocols),
        compilation_context = compilation_context,
        is_system = is_system,
        name = name,
        swift = swift,
    )

def create_clang_module(
        *,
        compilation_context,
        module_map,
        precompiled_module = None,
        strict_includes = None):
    """Creates a value representing a Clang module used as a Swift dependency.

    Args:
        compilation_context: A `CcCompilationContext` that contains the header
            files and other context (such as include paths, preprocessor
            defines, and so forth) needed to compile this module as an explicit
            module.
        module_map: The text module map file that defines this module. This
            argument may be specified as a `File` or as a `string`; in the
            latter case, it is assumed to be the path to a file that cannot
            be provided as an action input because it is outside the workspace
            (for example, the module map for a module from an Xcode SDK).
        precompiled_module: A `File` representing the precompiled module (`.pcm`
            file) if one was emitted for the module. This may be `None` if no
            explicit module was built for the module; in that case, targets that
            depend on the module will fall back to the text module map and
            headers.
        strict_includes: A `depset` of strings representing additional Clang
            include paths that should be passed to the compiler when this module
            is a _direct_ dependency of the module being compiled. May be
            `None`. **This field only exists to support a specific legacy use
            case and should otherwise not be used, as it is fundamentally
            incompatible with Swift's import model.**

    Returns:
        A `struct` containing the `compilation_context`, `module_map`,
        `precompiled_module`, and `strict_includes` fields provided as
        arguments.
    """
    return struct(
        compilation_context = compilation_context,
        module_map = module_map,
        precompiled_module = precompiled_module,
        strict_includes = strict_includes,
    )

def create_swift_module(
        *,
        swiftdoc,
        swiftmodule,
        ast_files = [],
        defines = [],
        indexstore = None,
        plugins = [],
        swiftsourceinfo = None,
        swiftinterface = None,
        private_swiftinterface = None,
        const_protocols_to_gather = [],
        symbol_graph = None):
    """Creates a value representing a Swift module use as a Swift dependency.

    Args:
        swiftdoc: The `.swiftdoc` file emitted by the compiler for this module.
        swiftmodule: The `.swiftmodule` file emitted by the compiler for this
            module.
        ast_files: A list of `File`s output from the `DUMP_AST` action.
        defines: A list of defines that will be provided as `copts` to targets
            that depend on this module. If omitted, the empty list will be used.
        indexstore: A `File` representing the directory that contains the index
            store data generated by the compiler if the
            `"swift.index_while_building"` feature is enabled, otherwise this
            will be `None`.
        plugins: A list of `SwiftCompilerPluginInfo` providers representing
            compiler plugins that are required by this module and should be
            loaded by the compiler when this module is directly depended on.
        private_swiftinterface: The `.private.swiftinterface` file emitted by
            the compiler for this module. May be `None` if no private module
            interface file was emitted.
        swiftsourceinfo: The `.swiftsourceinfo` file emitted by the compiler for
            this module. May be `None` if no source info file was emitted.
        swiftinterface: The `.swiftinterface` file emitted by the compiler for
            this module. May be `None` if no module interface file was emitted.
        const_protocols_to_gather: A list of protocol names from which constant
            values should be extracted from source code that takes this module
            as a *direct* dependency.
        symbol_graph: A `File` representing the directory that contains the
            symbol graph data generated by the compiler if the
            `"swift.emit_symbol_graph"` feature is enabled, otherwise this will
            be `None`.

    Returns:
        A `struct` containing the `ast_files`, `defines`, `indexstore,
        `swiftdoc`, `swiftmodule`, `swiftinterface`, and `symbol_graph` fields
        provided as arguments.
    """
    return struct(
        ast_files = tuple(ast_files),
        defines = tuple(defines),
        plugins = plugins,
        private_swiftinterface = private_swiftinterface,
        indexstore = indexstore,
        swiftdoc = swiftdoc,
        swiftinterface = swiftinterface,
        swiftmodule = swiftmodule,
        swiftsourceinfo = swiftsourceinfo,
        const_protocols_to_gather = tuple(const_protocols_to_gather),
        symbol_graph = symbol_graph,
    )

def create_swift_info(
        *,
        direct_swift_infos = [],
        modules = [],
        swift_infos = []):
    """Creates a new `SwiftInfo` provider with the given values.

    This function is recommended instead of directly creating a `SwiftInfo`
    provider because it encodes reasonable defaults for fields that some rules
    may not be interested in and ensures that the direct and transitive fields
    are set consistently.

    This function can also be used to do a simple merge of `SwiftInfo`
    providers, by leaving the `modules` argument unspecified. In that case, the
    returned provider will not represent a true Swift module; it is merely a
    "collector" for other dependencies.

    Args:
        direct_swift_infos: A list of `SwiftInfo` providers from dependencies
            whose direct modules should be treated as direct modules in the
            resulting provider, in addition to their transitive modules being
            merged.
        modules: A list of values (as returned by `swift_common.create_module`)
            that represent Clang and/or Swift module artifacts that are direct
            outputs of the target being built.
        swift_infos: A list of `SwiftInfo` providers from dependencies whose
            transitive modules should be merged into the resulting provider.

    Returns:
        A new `SwiftInfo` provider with the given values.
    """

    direct_modules = modules + [
        module
        for provider in direct_swift_infos
        for module in provider.direct_modules
    ]
    transitive_modules = [
        provider.transitive_modules
        for provider in direct_swift_infos + swift_infos
    ]

    return SwiftInfo(
        direct_modules = direct_modules,
        transitive_modules = depset(
            direct_modules,
            transitive = transitive_modules,
        ),
    )
