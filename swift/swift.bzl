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
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    _SwiftInfo = "SwiftInfo",
    _SwiftProtoInfo = "SwiftProtoInfo",
    _SwiftToolchainInfo = "SwiftToolchainInfo",
    _SwiftUsageInfo = "SwiftUsageInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_binary_test.bzl",
    _swift_binary = "swift_binary",
    _swift_test = "swift_test",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_c_module.bzl",
    _swift_c_module = "swift_c_module",
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
    "@build_bazel_rules_swift//swift/internal:swift_feature_allowlist.bzl",
    _swift_feature_allowlist = "swift_feature_allowlist",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_grpc_library.bzl",
    _swift_grpc_library = "swift_grpc_library",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_import.bzl",
    _swift_import = "swift_import",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_library.bzl",
    _swift_library = "swift_library",
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
    "@build_bazel_rules_swift//swift/internal:swift_proto_library.bzl",
    _swift_proto_library = "swift_proto_library",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_usage_aspect.bzl",
    _swift_usage_aspect = "swift_usage_aspect",
)

# Re-export providers.
SwiftInfo = _SwiftInfo
SwiftProtoInfo = _SwiftProtoInfo
SwiftToolchainInfo = _SwiftToolchainInfo
SwiftUsageInfo = _SwiftUsageInfo

# Re-export public API module.
swift_common = _swift_common

# Re-export rules.
swift_binary = _swift_binary
swift_c_module = _swift_c_module
swift_feature_allowlist = _swift_feature_allowlist
swift_grpc_library = _swift_grpc_library
swift_import = _swift_import
swift_library = _swift_library
swift_module_alias = _swift_module_alias
swift_package_configuration = _swift_package_configuration
swift_proto_library = _swift_proto_library
swift_test = _swift_test

# Re-export public aspects.
swift_clang_module_aspect = _swift_clang_module_aspect
swift_usage_aspect = _swift_usage_aspect
