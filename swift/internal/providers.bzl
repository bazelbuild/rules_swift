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

SwiftProtoInfo = provider(
    doc = "Propagates Swift-specific information about a `proto_library`.",
    fields = {
        "module_mappings": """\
`Sequence` of `struct`s. Each struct contains `module_name` and
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

SwiftToolchainInfo = provider(
    doc = """
Propagates information about a Swift toolchain to compilation and linking rules
that use the toolchain.
""",
    fields = {
        "action_configs": """\
This field is an internal implementation detail of the build rules.
""",
        "all_files": """\
A `depset` of `File`s containing all the Swift toolchain files (tools,
libraries, and other resource files) so they can be passed as `tools` to actions
using this toolchain.
""",
        "cc_toolchain_info": """\
The `cc_common.CcToolchainInfo` provider from the Bazel C++ toolchain that this
Swift toolchain depends on.
""",
        "cpu": """\
`String`. The CPU architecture that the toolchain is targeting.
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
        "linker_opts_producer": """\
Skylib `partial`. A partial function that returns the flags that should be
passed to Clang to link a binary or test target with the Swift runtime
libraries.

The partial should be called with two arguments:

*   `is_static`: A `Boolean` value indicating whether to link against the static
    or dynamic runtime libraries.

*   `is_test`: A `Boolean` value indicating whether the target being linked is a
    test target.
""",
        "linker_supports_filelist": """\
`Boolean`. Indicates whether or not the toolchain's linker supports the input
files passed to it via a file list.
""",
        "object_format": """\
`String`. The object file format of the platform that the toolchain is
targeting. The currently supported values are `"elf"` and `"macho"`.
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
        "supports_objc_interop": """\
`Boolean`. Indicates whether or not the toolchain supports Objective-C interop.
""",
        "swift_worker": """\
`File`. The executable representing the worker executable used to invoke the
compiler and other Swift tools (for both incremental and non-incremental
compiles).
""",
        "system_name": """\
`String`. The name of the operating system that the toolchain is targeting.
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
depends on, and specifically which toolchain was used.
""",
    fields = {
        "toolchain": """\
The Swift toolchain that was used to build the targets propagating this
provider.
""",
    },
)

def create_module(*, name, clang = None, is_system = False, swift = None):
    """Creates a value containing Clang/Swift module artifacts of a dependency.

    At least one of the `clang` and `swift` arguments must not be `None`. It is
    valid for both to be present; this is the case for most Swift modules, which
    provide both Swift module artifacts as well as a generated header/module map
    for Objective-C targets to depend on.

    Args:
        name: The name of the module.
        clang: A value returned by `swift_common.create_clang_module` that
            contains artifacts related to Clang modules, such as a module map or
            precompiled module. This may be `None` if the module is a pure Swift
            module with no generated Objective-C interface.
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
    if clang == None and swift == None:
        fail("Must provide at least a clang or swift module.")
    return struct(
        clang = clang,
        is_system = is_system,
        name = name,
        swift = swift,
    )

def create_clang_module(
        *,
        compilation_context,
        module_map,
        precompiled_module = None):
    """Creates a value representing a Clang module used as a Swift dependency.

    Args:
        compilation_context: A `CcCompilationContext` that contains the header
            files, include paths, and other context necessary to compile targets
            that depend on this module (if using the text module map instead of
            the precompiled module).
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

    Returns:
        A `struct` containing the `compilation_context`, `module_map`, and
        `precompiled_module` fields provided as arguments.
    """
    return struct(
        compilation_context = compilation_context,
        module_map = module_map,
        precompiled_module = precompiled_module,
    )

def create_swift_module(
        *,
        swiftdoc,
        swiftmodule,
        defines = [],
        swiftinterface = None):
    """Creates a value representing a Swift module use as a Swift dependency.

    Args:
        swiftdoc: The `.swiftdoc` file emitted by the compiler for this module.
        swiftmodule: The `.swiftmodule` file emitted by the compiler for this
            module.
        defines: A list of defines that will be provided as `copts` to targets
            that depend on this module. If omitted, the empty list will be used.
        swiftinterface: The `.swiftinterface` file emitted by the compiler for
            this module. May be `None` if no module interface file was emitted.

    Returns:
        A `struct` containing the `defines`, `swiftdoc`, `swiftmodule`, and
        `swiftinterface` fields provided as arguments.
    """
    return struct(
        defines = defines,
        swiftdoc = swiftdoc,
        swiftinterface = swiftinterface,
        swiftmodule = swiftmodule,
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
        provider.modules
        for provider in direct_swift_infos
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
