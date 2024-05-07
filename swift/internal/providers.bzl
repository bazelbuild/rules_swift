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

"""Internal providers."""

SwiftCompilerPluginInfo = provider(
    doc = """
Information about compiler plugins (like macros) that is needed by the compiler
when loading modules that declare those macros.
""",
    fields = {
        "executable": "A `File` representing the plugin's binary executable.",
        "module_names": """\
A `depset` of strings denoting the names of the Swift modules that provide
plugin types looked up by the compiler. This currently contains a single
element, the name of the module created by the `swift_compiler_plugin` target.
""",
    },
)

SwiftCrossImportOverlayInfo = provider(
    doc = "Information about a cross-import overlay module.",
    fields = {
        "bystanding_module": """\
The name of the bystanding module in the cross-import.
""",
        "declaring_module": """\
The name of the declaring module in the cross-import.
""",
        "swift_infos": """\
A list of `SwiftInfo` providers that describe the cross-import overlay modules
that should be injected into the dependencies of a compilation when both the
`declaring_module` and `bystanding_module` are imported.
""",
    },
)

SwiftModuleAliasesInfo = provider(
    doc = "Defines a remapping of Swift module names.",
    fields = {
        "aliases": """\
A string-to-string dictionary that contains aliases for Swift modules.
Each key in the dictionary is the name of a module as it is written in source
code. The corresponding value is the replacement module name to use when
compiling it and/or any modules that depend on it.
""",
    },
)

SwiftOverlayCompileInfo = provider(
    doc = """\
Propagated by the `swift_overlay` rule to represent information needed to
compile a Swift overlay with its paired C/Objective-C module.
""",
    fields = {
        "label": "The label of the `swift_overlay` target.",
        "srcs": "The source files to compile in the overlay.",
        "additional_inputs": "Additional inputs to the compiler.",
        "copts": """\
List of strings. Swift compiler flags to pass when compiling the overlay.
""",
        "defines": """\
List of strings. Compiler conditions to set when compiling the overlay.
""",
        "disabled_features": """\
List of strings. Features that should be disabled when compiling the overlay.
""",
        "enabled_features": """\
List of strings. Features that should be enabled when compiling the overlay.
""",
        "include_dev_srch_paths": """\
Bool. Whether to add the developer framework search paths when compiling the
overlay.
""",
        "library_evolution": """\
Bool. Whether to compile the overlay with library evolution enabled.
""",
        "linkopts": """\
List of strings. Linker flags to propagate when the overlay is used as a
dependency.
""",
        "plugins": """\
A list of `SwiftCompilerPluginInfo` providers of the overlay's plug-ins.
""",
        "private_deps": """\
A `struct` containing the following fields:

*   `cc_infos`: A list of `CcInfo` providers from the overlay's `private_deps`.
*   `swift_infos`: A list of `SwiftInfo` providers from the overlay's
    `private_deps`.
""",
        "alwayslink": """\
Bool. Whether the overlay should always be included in the final binary's
linkage.
""",
        "deps": """\
A `struct` containing the following fields:

*   `cc_infos`: A list of `CcInfo` providers from the overlay's `deps`.
*   `swift_infos`: A list of `SwiftInfo` providers from the overlay's `deps`.
""",
    },
)
