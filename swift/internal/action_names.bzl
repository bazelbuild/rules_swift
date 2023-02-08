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

"""Constants representing the names of actions spawned by the Swift rules."""

visibility([
    "@build_bazel_rules_swift//swift/toolchains/...",
])

# Compiles one or more `.swift` source files into a `.swiftmodule` and
# object files.
SWIFT_ACTION_COMPILE = "SwiftCompile"

# Compiles a `.swiftinterface` file into a `.swiftmodule` file.
SWIFT_ACTION_COMPILE_MODULE_INTERFACE = "SwiftCompileModuleInterface"

# Wraps a `.swiftmodule` in a `.o` file on ELF platforms so that it can be
# linked into a binary for debugging.
SWIFT_ACTION_MODULEWRAP = "SwiftModuleWrap"

# Precompiles an explicit module for a C/Objective-C module map and its
# headers, emitting a `.pcm` file.
SWIFT_ACTION_PRECOMPILE_C_MODULE = "SwiftPrecompileCModule"

# Extracts a JSON-formatted symbol graph from a module, which can be used as
# an input to documentation generating tools like `docc` or analyzed with
# other tooling.
SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT = "SwiftSymbolGraphExtract"

def all_action_names():
    """A convenience function to return all actions defined by this rule set."""
    return (
        SWIFT_ACTION_COMPILE,
        SWIFT_ACTION_COMPILE_MODULE_INTERFACE,
        SWIFT_ACTION_MODULEWRAP,
        SWIFT_ACTION_PRECOMPILE_C_MODULE,
        SWIFT_ACTION_SYMBOL_GRAPH_EXTRACT,
    )
