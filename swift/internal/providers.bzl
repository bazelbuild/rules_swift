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

"""Defines Skylark providers that propagated by the Swift BUILD rules."""

SwiftInfo = provider(
    doc = """
Contains information about the compiled artifacts of a Swift module.

This provider contains a large number of fields and many custom rules may not need to set all of
them. Instead of constructing a `SwiftInfo` provider directly, consider using the
`swift_common.create_swift_info` function, which has reasonable defaults for any fields not
explicitly set.
""",
    fields = {
        "direct_defines": """
`List` of `string`s. The values specified by the `defines` attribute of the library that directly
propagated this provider.
""",
        "direct_swiftdocs": """
`List` of `File`s. The Swift documentation (`.swiftdoc`) files for the library that directly
propagated this provider.
""",
        "direct_swiftmodules": """
`List` of `File`s. The Swift modules (`.swiftmodule`) for the library that directly propagated this
provider.
""",
        "module_name": """
`String`. The name of the Swift module represented by the target that directly propagated this
provider.

This field will be equal to the explicitly assigned module name (if present); otherwise, it will be
equal to the autogenerated module name.
""",
        "swift_version": """
`String`. The version of the Swift language that was used when compiling the propagating target;
that is, the value passed via the `-swift-version` compiler flag. This will be `None` if the flag
was not set.
""",
        "transitive_defines": """
`Depset` of `string`s. The transitive `defines` specified for the library that propagated this
provider and all of its dependencies.
""",
        "transitive_modulemaps": """
`Depset` of `File`s. The transitive module map files that will be passed to Clang using the
`-fmodule-map-file` option.
""",
        "transitive_swiftdocs": """
`Depset` of `File`s. The transitive Swift documentation (`.swiftdoc`) files emitted by the library
that propagated this provider and all of its dependencies.
""",
        "transitive_swiftinterfaces": """
`Depset` of `File`s. The transitive Swift interface (`.swiftinterface`) files emitted by the library
that propagated this provider and all of its dependencies.
""",
        "transitive_swiftmodules": """
`Depset` of `File`s. The transitive Swift modules (`.swiftmodule`) emitted by the library that
propagated this provider and all of its dependencies.
""",
    },
)

SwiftProtoInfo = provider(
    doc = "Propagates Swift-specific information about a `proto_library`.",
    fields = {
        "module_mappings": """
`Sequence` of `struct`s. Each struct contains `module_name` and `proto_file_paths` fields that
denote the transitive mappings from `.proto` files to Swift modules. This allows messages that
reference messages in other libraries to import those modules in generated code.
""",
        "pbswift_files": """
`Depset` of `File`s. The transitive Swift source files (`.pb.swift`) generated from the `.proto`
files.
""",
    },
)

SwiftToolchainInfo = provider(
    doc = """
Propagates information about a Swift toolchain to compilation and linking rules that use the
toolchain.
""",
    fields = {
        "action_environment": """
`Dict`. Environment variables that should be set during any actions spawned to compile or link Swift
code.
""",
        "all_files": """
A `depset` of `File`s containing all the Swift toolchain files (tools, libraries, and other resource
files) so they can be passed as `tools` to actions using this toolchain.
""",
        "cc_toolchain_info": """
The `cc_common.CcToolchainInfo` provider from the Bazel C++ toolchain that this Swift toolchain
depends on.
""",
        "clang_executable": """
`String`. The path to the `clang` executable, which is used to link binaries.
""",
        "command_line_copts": """
`List` of `strings`. Flags that were passed to Bazel using the `--swiftcopt` command line flag.
These flags have the highest precedence; they are added to compilation command lines after the
toolchain default flags (`SwiftToolchainInfo.swiftc_copts`) and after flags specified in the
`copts` attributes of Swift targets.
""",
        "cpu": "`String`. The CPU architecture that the toolchain is targeting.",
        "execution_requirements": """
`Dict`. Execution requirements that should be passed to any actions spawned to compile or link
Swift code.

For example, when using an Xcode toolchain, the execution requirements should be such that running
on Darwin is required.
""",
        "linker_opts_producer": """
Skylib `partial`. A partial function that returns the flags that should be passed to Clang to link a
binary or test target with the Swift runtime libraries.

The partial should be called with two arguments:

*   `is_static`: A `Boolean` value indicating whether to link against the static or dynamic runtime
    libraries.
*   `is_test`: A `Boolean` value indicating whether the target being linked is a test target.
""",
        "object_format": """
`String`. The object file format of the platform that the toolchain is targeting. The currently
supported values are `"elf"` and `"macho"`.
""",
        "optional_implicit_deps": """
`List` of `Target`s. Library targets that should be added as implicit dependencies of any
`swift_library`, `swift_binary`, or `swift_test` target that does not have the feature
`swift.minimal_deps` applied.
""",
        "requested_features": """
`List` of `string`s. Features that should be implicitly enabled by default for targets built using
this toolchain, unless overridden by the user by listing their negation in the `features` attribute
of a target/package or in the `--features` command line flag.

These features determine various compilation and debugging behaviors of the Swift build rules, and
they are also passed to the C++ APIs used when linking (so features defined in CROSSTOOL may be used
here).
""",
        "required_implicit_deps": """
`List` of `Target`s. Library targets that should be unconditionally added as implicit dependencies
of any `swift_library`, `swift_binary`, or `swift_test` target.
""",
        "root_dir": "`String`. The workspace-relative root directory of the toolchain.",
        "stamp_producer": """
Skylib `partial`. A partial function that compiles build data that should be stamped into binaries.
This value may be `None` if the toolchain does not support link stamping.

The `swift_binary` and `swift_test` rules call this function _whether or not_ link stamping is
enabled for that target. This provides toolchains the option of still linking fixed placeholder
data into the binary if desired, instead of linking nothing at all. Whether stamping is enabled can
be checked by inspecting `ctx.attr.stamp` inside the partial's implementation.

The rule implementation will call this partial and pass it the following four arguments:

*    `ctx`: The rule context of the target being built.
*    `cc_feature_configuration`: The C++ feature configuration to use when compiling the stamp
     code.
*    `cc_toolchain`: The C++ toolchain (`CcToolchainInfo` provider) to use when compiling the
     stamp code.
*    `binary`: The `File` object representing the binary being linked.

The partial should return a `CcLinkingContext` containing the data (such as object files) to be
linked into the binary, or `None` if nothing should be linked into the binary.
""",
        "supports_objc_interop": """
`Boolean`. Indicates whether or not the toolchain supports Objective-C interop.
""",
        "swiftc_copts": """
`List` of `strings`. Additional flags that should be passed to `swiftc` when compiling libraries or
binaries with this toolchain. These flags will come first in compilation command lines, allowing
them to be overridden by `copts` attributes and `--swiftcopt` flags.
""",
        "swift_worker": """
`File`. The executable representing the worker executable used to invoke the compiler and other
Swift tools (for both incremental and non-incremental compiles).
""",
        "system_name": """
`String`. The name of the operating system that the toolchain is targeting.
""",
        "unsupported_features": """
`List` of `string`s. Features that should be implicitly disabled by default for targets built using
this toolchain, unless overridden by the user by listing them in the `features` attribute of a
target/package or in the `--features` command line flag.

These features determine various compilation and debugging behaviors of the Swift build rules, and
they are also passed to the C++ APIs used when linking (so features defined in CROSSTOOL may be used
here).
""",
    },
)

SwiftUsageInfo = provider(
    doc = """
A provider that indicates that Swift was used by a target or any target that it depends on, and
specifically which toolchain was used.
""",
    fields = {
        "toolchain": """
The Swift toolchain that was used to build the targets propagating this provider.
""",
    },
)
