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

visibility([
    "@build_bazel_rules_swift//swift/...",
])

SwiftBinaryInfo = provider(
    doc = """
Information about a binary target's module.

`swift_binary` and `swift_compiler_plugin` propagate this provider that wraps
`CcInfo` and `SwiftInfo` providers, instead of propagating them directly, so
that `swift_test` targets can depend on those binaries and test their modules
(similar to what Swift Package Manager allows) without allowing any
`swift_library` to depend on an arbitrary binary.
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
