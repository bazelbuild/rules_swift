# Copyright 2019 The Bazel Authors. All rights reserved.
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

"""Utilities for rules/aspects that generate sources from .proto files."""

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def swift_proto_lang_toolchain_label():
    """A `Label` for the `proto_lang_toolchain` target for Swift Protos

    This data is needed for both the aspect and the rule itself, so this
    keeps the two values in sync.

    Returns:
        A `Label` that is the `proto_lang_toolchain` target to be used for
        `swift_proto_library`.
    """
    return Label("@build_bazel_rules_swift//swift/internal:proto_swift_toolchain")
