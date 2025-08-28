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

"""Defines providers propagated by the Swift BUILD rules and related utilities.

This file must be kept lightweight and not load any other `.bzl` files that may
update frequently (e.g., other files in rules_swift). This ensures that changes
to the rule implementations do not unnecessarily cause reanalysis impacting
users who just load these providers to inspect and/or repropagate them.
"""

visibility("public")

SwiftBinaryInfo = provider(
    doc = """
Information about a binary target's module.

`swift_binary` and `swift_compiler_plugin` propagate this provider that wraps
`CcInfo` and `SwiftInfo` providers, instead of propagating them directly, so
that `swift_test` targets can depend on those binaries and test their modules
(similar to what Swift Package Manager allows) without allowing any
`swift_library` to depend on an arbitrary binary.

Aside from these use cases, this provider should only be consumed by clients
like IDEs, debuggers, and other language tooling that need access to the Swift
module produced by compiling a binary target. Other uses are unsupported.
""",
    fields = {
        "cc_info": """\
A `CcInfo` provider containing the binary's code compiled as a static library,
which is suitable for linking into a `swift_test` so that unit tests can be
written against it.

Notably, this `CcInfo`'s linking context does *not* contain the linker flags
used to alias the `main` entry point function, because the purpose of this
provider is to allow it to be linked into another binary that would provide its
own entry point instead.
""",
        "swift_info": """\
A `SwiftInfo` provider representing the Swift module created by compiling the
target. This is used specifically by `swift_test` to allow test code to depend
on the binary's module without making it possible for arbitrary libraries or
binaries to depend on other binaries.
""",
    },
)

SwiftFeatureAllowlistInfo = provider(
    doc = """\
Describes a set of features and the packages and aspects that are allowed to
request or disable them.

This provider is an internal implementation detail of the rules; users should
not rely on it or assume that its structure is stable.
""",
    fields = {
        "allowlist_label": """\
A string containing the label of the `swift_feature_allowlist` target that
created this provider.
""",
        "aspect_ids": """\
A list of strings representing identifiers of aspects that are allowed to
request or disable a feature managed by the allowlist, even when the target the
aspect is being applied to does not match `package_specs`.
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

def _swift_info_init(
        *,
        direct_swift_infos = [],
        modules = [],
        swift_infos = []):
    """Creates a `SwiftInfo` provider from the given arguments.

    Args:
        direct_swift_infos: A list of `SwiftInfo` providers from dependencies
            whose direct modules should be treated as direct modules in the resulting
            provider, in addition to their transitive modules being merged.
        modules: A list of values (as returned by `create_swift_module_context()`)
            that represent Clang and/or Swift module artifacts that are direct outputs
            of the target being built.
        swift_infos: A list of `SwiftInfo` providers from dependencies whose
            transitive modules should be merged into the resulting provider.
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

    return {
        "direct_modules": direct_modules,
        "transitive_modules": depset(
            direct_modules,
            transitive = transitive_modules,
        ),
    }

SwiftInfo, _create_raw_swift_info = provider(
    doc = "Contains information about the compiled artifacts of a Swift module.",
    fields = {
        "direct_modules": """\
`List` of values returned from `create_swift_module_context`. The modules (both
Swift and C/Objective-C) emitted by the library that propagated this provider.
""",
        "transitive_modules": """\
`Depset` of values returned from `create_swift_module_context`. The transitive
modules (both Swift and C/Objective-C) emitted by the library that propagated
this provider and all of its dependencies.
""",
    },
    init = _swift_info_init,
)

SwiftOverlayInfo = provider(
    doc = """\
Contains additional artifacts from the Swift overlay for a C/Objective-C module
that also need to be propagated to clients of the module for it to work
properly.
""",
    fields = {
        "linking_context": """\
`CcLinkingContext`. A linking context that contain object files, linker flags,
and additional linker inputs for Swift code that was compiled as an overlay for
a C/Objective-C target.
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

SwiftProtoInfo = provider(
    doc = "Propagates Swift-specific information about a `proto_library`.",
    fields = {
        "module_mappings": """\
`Depset` of `struct`s. Each struct contains `module_name` and
`proto_file_paths` fields that denote the transitive mappings from `.proto`
files to Swift modules. This allows messages that reference messages in other
libraries to import those modules in generated code.
""",
        "pbswift_files": """\
`Depset` of `File`s. The transitive Swift source files (`.pb.swift`) generated
from the `.proto` files.
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

SwiftSynthesizedInterfaceInfo = provider(
    doc = "Propagates synthesized Swift interfaces for modules.",
    fields = {
        "direct_modules": """\
`List` of `struct`s representing the synthesized interfaces for the modules in
the target that propagated this provider. This list will be empty if propagated
by a target that does not contain any modules that Swift can synthesize an
interface for (i.e., C, or Swift itself), but its `transitive_modules` may be
non-empty if it has dependencies for which interfaces can be synthesized.

Each `struct` has the following fields:

*   `module_name`: A string denoting the name of the module whose interface is
    synthesized.

*   `synthesized_interface`: A `File` containing the synthesized interface.
""",
        "transitive_modules": """\
`Depset` of `struct`s representing the synthesized interfaces for the modules in
the target that propagated this provider and all of its dependencies. Each
`struct` has the same fields as documented in `direct_modules`.
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
        "builtin_headers": """\
A `depset` of `File`s containing the compiler's built-in headers, if customized,
otherwise None.
""",
        "builtin_headers_path": """\
The path to the location of the compiler's built-in headers, if customized,
otherwise None.
""",
        "cc_language": """\
The `language` that should be passed to `cc_common` APIs that take it as an
argument.
""",
        "clang_implicit_deps_providers": """\
A `struct` with the following fields, which represent providers from targets
that should be added as implicit dependencies of any precompiled explicit
C/Objective-C modules:

*   `cc_infos`: A list of `CcInfo` providers from targets specified as the
    toolchain's implicit dependencies.

*   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the
    toolchain's implicit dependencies.

For ease of use, this field is never `None`; it will always be a valid `struct`
containing the fields described above, even if those lists are empty.
""",
        "codegen_batch_size": """\
The number of files to pass to the compiler in a single code generation action
(one that compiles object files from Swift source files).
""",
        "cross_import_overlays": """\
A list of `SwiftCrossImportOverlayInfo` providers whose `SwiftInfo` providers
will be automatically injected into the dependencies of Swift compilations if
their declaring module and bystanding module are both already declared as
dependencies.
""",
        "debug_outputs_provider": """\
An optional function that provides toolchain-specific logic around the handling
of additional debug outputs for `swift_binary` and `swift_test` targets.

If specified, this function must take the following keyword arguments:

*   `ctx`: The rule context of the calling binary or test rule.

It must return a `struct` with the following fields:

*   `additional_outputs`: Additional outputs expected from the linking action.

*   `variables_extension`: A dictionary of additional crosstool variables to
    pass to the linking action.
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

*   `swift_infos`: A list of `SwiftInfo` providers from targets specified as the
    toolchain's implicit dependencies.

For ease of use, this field is never `None`; it will always be a valid `struct`
containing the fields described above, even if those lists are empty.
""",
        "module_aliases": """\
A `SwiftModuleAliasesInfo` provider that defines the module aliases to use
during compilation.
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
`Struct` containing the following fields:

*   `binary_name`: A template string used to compute the name of the output
    binary for `swift_test` rules. Any occurrences of the string `"{name}"` will
    be substituted by the name of the target.

*   `env`: A `dict` of environment variables to be set when running tests
    that were built with this toolchain.

*   `execution_requirements`: A `dict` of execution requirements for tests
    that were built with this toolchain.

*   `objc_test_discovery`: A Boolean value indicating whether test targets
    should discover tests dynamically using the Objective-C runtime.

*   `test_linking_contexts`: A list of `CcLinkingContext`s that provide
    additional flags to use when linking test binaries.

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

SwiftClangModuleAspectInfo = provider(
    doc = """\
A "marker provider" (i.e., it has no fields) that is always returned when
`swift_clang_module_aspect` is applied to a target.

This provider exists because `swift_clang_module_aspect` cannot advertise that
it returns `SwiftInfo` (since some code paths do not). Users who want to ensure
aspect ordering via the `required_aspect_providers` parameter to their own
`aspect` function can require this provider instead, which
`swift_clang_module_aspect` does advertise.
""",
    fields = {},
)

def create_swift_module_context(
        *,
        name,
        clang = None,
        const_gather_protocols = [],
        is_framework = False,
        is_system = False,
        source_name = None,
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
        name: The name of the module. If this module is aliased, then this is
            not the name of the module as one would write in source to reference
            it, but the *physical* name of the module used when it was compiled.
        clang: A value returned by `create_clang_module_inputs` that
            contains artifacts related to Clang modules, such as a module map or
            precompiled module. This may be `None` if the module is a pure Swift
            module with no generated Objective-C interface.
        const_gather_protocols: A list of protocol names from which constant
            values should be extracted from source code that takes this module
            as a *direct* dependency.
        is_framework: Indictates whether the module is a framework module. The
            default value is `False`.
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
        source_name: The name that should be used when referencing the module
            from source code. If the module is aliased, then this is the
            original name of the module, not its new physical name. This
            argument is optional; if it is not provided, then `name` is used
            instead.
        swift: A value returned by `create_swift_module_inputs` that
            contains artifacts related to Swift modules, such as the
            `.swiftmodule`, `.swiftdoc`, and/or `.swiftinterface` files emitted
            by the compiler. This may be `None` if the module is a pure
            C/Objective-C module.

    Returns:
        A `struct` containing the given values provided as arguments.
    """
    return struct(
        clang = clang,
        const_gather_protocols = tuple(const_gather_protocols),
        is_framework = is_framework,
        is_system = is_system,
        name = name,
        source_name = source_name or name,
        swift = swift,
    )

def create_clang_module_inputs(
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
        A `struct` containing the values provided as arguments.
    """
    return struct(
        compilation_context = compilation_context,
        module_map = module_map,
        precompiled_module = precompiled_module,
        strict_includes = strict_includes,
    )

def create_swift_module_inputs(
        *,
        defines = [],
        plugins = [],
        swiftdoc,
        swiftinterface = None,
        swiftmodule,
        swiftsourceinfo = None):
    """Creates a value representing a Swift module use as a Swift dependency.

    Args:
        defines: A list of defines that will be provided as `copts` to targets
            that depend on this module. If omitted, the empty list will be used.
        plugins: A list of `SwiftCompilerPluginInfo` providers representing
            compiler plugins that are required by this module and should be
            loaded by the compiler when this module is directly depended on.
        swiftdoc: The `.swiftdoc` file emitted by the compiler for this module.
        swiftinterface: The `.swiftinterface` file emitted by the compiler for
            this module. May be `None` if no module interface file was emitted.
        swiftmodule: The `.swiftmodule` file emitted by the compiler for this
            module.
        swiftsourceinfo: The `.swiftsourceinfo` file emitted by the compiler for
            this module. May be `None` if no source info file was emitted.

    Returns:
        A `struct` containing the values provided as arguments.
    """
    return struct(
        defines = defines,
        plugins = plugins,
        swiftdoc = swiftdoc,
        swiftinterface = swiftinterface,
        swiftmodule = swiftmodule,
        swiftsourceinfo = swiftsourceinfo,
    )
