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
"""

load(
    "@build_bazel_rules_swift//swift/internal:api.bzl",
    _swift_common="swift_common",
)
load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    _SwiftBinaryInfo="SwiftBinaryInfo",
    _SwiftClangModuleInfo="SwiftClangModuleInfo",
    _SwiftInfo="SwiftInfo",
    _SwiftProtoInfo="SwiftProtoInfo",
    _SwiftToolchainInfo="SwiftToolchainInfo",
    _SwiftUsageInfo="SwiftUsageInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_binary_test.bzl",
    _swift_binary="swift_binary",
    _swift_test="swift_test",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_c_module.bzl",
    _swift_c_module="swift_c_module",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_import.bzl",
    _swift_import="swift_import",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_library.bzl",
    _swift_library="swift_library",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_module_alias.bzl",
    _swift_module_alias="swift_module_alias",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_proto_library.bzl",
    _swift_proto_library="swift_proto_library",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_usage_aspect.bzl",
    _swift_usage_aspect="swift_usage_aspect",
)

# Re-export providers.
SwiftBinaryInfo = _SwiftBinaryInfo
SwiftClangModuleInfo = _SwiftClangModuleInfo
SwiftInfo = _SwiftInfo
SwiftProtoInfo = _SwiftProtoInfo
SwiftToolchainInfo = _SwiftToolchainInfo
SwiftUsageInfo = _SwiftUsageInfo

# Re-export public API module.
swift_common = _swift_common

# Re-export rules.
swift_binary = _swift_binary
swift_c_module = _swift_c_module
swift_import = _swift_import
swift_library = _swift_library
swift_test = _swift_test
swift_module_alias = _swift_module_alias
swift_proto_library = _swift_proto_library

# Re-export public aspects.
swift_usage_aspect = _swift_usage_aspect
