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
`Struct` containing the following fields:

*   `env`: A `dict` of environment variables to be set when running tests
    that were built with this toolchain.

*   `execution_requirements`: A `dict` of execution requirements for tests
    that were built with this toolchain.

*   `uses_xctest_bundles`: A Boolean value indicating whether test targets
    should emit `.xctest` bundles that are launched with the `xctest` tool.

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
