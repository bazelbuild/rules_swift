# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Re-exported symbols for consumption from stardoc.
"""

load(
    "//proto:proto.bzl",
    # providers
    _SwiftProtoCompilerInfo = "SwiftProtoCompilerInfo",
    _SwiftProtoInfo = "SwiftProtoInfo",
    # api
    _swift_proto_common = "swift_proto_common",
    # rules
    _swift_proto_compiler = "swift_proto_compiler",
    _swift_proto_library = "swift_proto_library",
)
load(
    "//swift:swift.bzl",
    # providers
    _SwiftGRPCInfo = "SwiftGRPCInfo",
    _SwiftInfo = "SwiftInfo",
    _SwiftToolchainInfo = "SwiftToolchainInfo",
    _SwiftUsageInfo = "SwiftUsageInfo",
    # rules
    _deprecated_swift_grpc_library = "deprecated_swift_grpc_library",
    _deprecated_swift_proto_library = "deprecated_swift_proto_library",
    _swift_binary = "swift_binary",
    _swift_c_module = "swift_c_module",
    # api
    _swift_common = "swift_common",
    _swift_compiler_plugin = "swift_compiler_plugin",
    _swift_feature_allowlist = "swift_feature_allowlist",
    _swift_import = "swift_import",
    _swift_library = "swift_library",
    _swift_library_group = "swift_library_group",
    _swift_module_alias = "swift_module_alias",
    _swift_package_configuration = "swift_package_configuration",
    _swift_test = "swift_test",
    # aspects
    _swift_usage_aspect = "swift_usage_aspect",
    _universal_swift_compiler_plugin = "universal_swift_compiler_plugin",
)

# proto symbols
swift_proto_common = _swift_proto_common
SwiftProtoCompilerInfo = _SwiftProtoCompilerInfo
SwiftProtoInfo = _SwiftProtoInfo
swift_proto_compiler = _swift_proto_compiler
swift_proto_library = _swift_proto_library

# swift symbols
swift_common = _swift_common
swift_usage_aspect = _swift_usage_aspect
SwiftGRPCInfo = _SwiftGRPCInfo
SwiftInfo = _SwiftInfo
SwiftToolchainInfo = _SwiftToolchainInfo
SwiftUsageInfo = _SwiftUsageInfo
deprecated_swift_grpc_library = _deprecated_swift_grpc_library
deprecated_swift_proto_library = _deprecated_swift_proto_library
swift_binary = _swift_binary
swift_c_module = _swift_c_module
swift_compiler_plugin = _swift_compiler_plugin
universal_swift_compiler_plugin = _universal_swift_compiler_plugin
swift_feature_allowlist = _swift_feature_allowlist
swift_import = _swift_import
swift_library = _swift_library
swift_library_group = _swift_library_group
swift_module_alias = _swift_module_alias
swift_package_configuration = _swift_package_configuration
swift_test = _swift_test
