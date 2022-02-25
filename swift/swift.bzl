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

"""BUILD rules to define Swift libraries and executable binaries.

This file is the public interface that users should import to use the Swift
rules. Do not import definitions from the `internal` subdirectory directly.

To use the Swift build rules in your BUILD files, load them from
`@build_bazel_rules_swift//swift:swift.bzl`.

For example:

```build
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
```
"""

load(
    "@build_bazel_rules_swift//swift:swift_compiler_plugin.bzl",
    _swift_compiler_plugin = "swift_compiler_plugin",
    _universal_swift_compiler_plugin = "universal_swift_compiler_plugin",
)
load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    _SwiftInfo = "SwiftInfo",
    _SwiftProtoCompilerInfo = "SwiftProtoCompilerInfo",
    _SwiftProtoInfo = "SwiftProtoInfo",
    _SwiftSymbolGraphInfo = "SwiftSymbolGraphInfo",
    _SwiftToolchainInfo = "SwiftToolchainInfo",
    _SwiftUsageInfo = "SwiftUsageInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_binary.bzl",
    _swift_binary = "swift_binary",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_clang_module_aspect.bzl",
    _swift_clang_module_aspect = "swift_clang_module_aspect",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_common.bzl",
    _swift_common = "swift_common",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_extract_symbol_graph.bzl",
    _swift_extract_symbol_graph = "swift_extract_symbol_graph",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_feature_allowlist.bzl",
    _swift_feature_allowlist = "swift_feature_allowlist",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_import.bzl",
    _swift_import = "swift_import",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_interop_hint.bzl",
    _swift_interop_hint = "swift_interop_hint",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_library.bzl",
    _swift_library = "swift_library",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_library_group.bzl",
    _swift_library_group = "swift_library_group",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_module_alias.bzl",
    _swift_module_alias = "swift_module_alias",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_package_configuration.bzl",
    _swift_package_configuration = "swift_package_configuration",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_symbol_graph_aspect.bzl",
    _swift_symbol_graph_aspect = "swift_symbol_graph_aspect",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_test.bzl",
    _swift_test = "swift_test",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_usage_aspect.bzl",
    _swift_usage_aspect = "swift_usage_aspect",
)

# Re-export providers.
SwiftInfo = _SwiftInfo
SwiftProtoCompilerInfo = _SwiftProtoCompilerInfo
SwiftProtoInfo = _SwiftProtoInfo
SwiftSymbolGraphInfo = _SwiftSymbolGraphInfo
SwiftToolchainInfo = _SwiftToolchainInfo
SwiftUsageInfo = _SwiftUsageInfo

# Re-export public API module.
swift_common = _swift_common

# Re-export rules.
swift_binary = _swift_binary
swift_compiler_plugin = _swift_compiler_plugin
universal_swift_compiler_plugin = _universal_swift_compiler_plugin
swift_extract_symbol_graph = _swift_extract_symbol_graph
swift_feature_allowlist = _swift_feature_allowlist
swift_import = _swift_import
swift_interop_hint = _swift_interop_hint
swift_library = _swift_library
swift_library_group = _swift_library_group
swift_module_alias = _swift_module_alias
swift_package_configuration = _swift_package_configuration
swift_test = _swift_test

# Re-export public aspects.
swift_clang_module_aspect = _swift_clang_module_aspect
swift_symbol_graph_aspect = _swift_symbol_graph_aspect
swift_usage_aspect = _swift_usage_aspect
