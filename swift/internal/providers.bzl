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
