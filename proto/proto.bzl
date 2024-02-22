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

"""Bazel rules to define Swift proto libraries and compilers."""

load(
    "//proto:swift_proto_common.bzl",
    _swift_proto_common = "swift_proto_common",
)
load(
    "//proto:swift_proto_compiler.bzl",
    _swift_proto_compiler = "swift_proto_compiler",
)
load(
    "//proto:swift_proto_library.bzl",
    _swift_proto_library = "swift_proto_library",
)
load(
    "//swift:swift.bzl",
    _SwiftProtoCompilerInfo = "SwiftProtoCompilerInfo",
    _SwiftProtoInfo = "SwiftProtoInfo",
)

# Export providers:
SwiftProtoCompilerInfo = _SwiftProtoCompilerInfo
SwiftProtoInfo = _SwiftProtoInfo

# Export rules:
swift_proto_compiler = _swift_proto_compiler
swift_proto_library = _swift_proto_library

# Export modules:
swift_proto_common = _swift_proto_common
