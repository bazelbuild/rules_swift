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

"""A resilient API layer wrapping compilation and other logic for Swift.

This module is meant to be used by custom rules that need to compile Swift code
and cannot simply rely on writing a macro that wraps `swift_library`. For
example, `swift_proto_library` generates Swift source code from `.proto` files
and then needs to compile them. This module provides that lower-level interface.

Do not load this file directly; instead, load the top-level `swift.bzl` file,
which exports the `swift_common` module.
"""

load(
    ":attrs.bzl",
    "swift_compilation_attrs",
    "swift_library_rule_attrs",
    "swift_toolchain_attrs",
)
load(":compiling.bzl", "compile", "derive_module_name", "get_implicit_deps")
load(
    ":features.bzl",
    "configure_features",
    "get_cc_feature_configuration",
    "is_feature_enabled",
)
load(":linking.bzl", "swift_runtime_linkopts")
load(":providers.bzl", "create_swift_info")

# The exported `swift_common` module, which defines the public API for directly
# invoking actions that compile Swift code from other rules.
swift_common = struct(
    cc_feature_configuration = get_cc_feature_configuration,
    compilation_attrs = swift_compilation_attrs,
    compile = compile,
    configure_features = configure_features,
    create_swift_info = create_swift_info,
    derive_module_name = derive_module_name,
    get_implicit_deps = get_implicit_deps,
    is_enabled = is_feature_enabled,
    library_rule_attrs = swift_library_rule_attrs,
    swift_runtime_linkopts = swift_runtime_linkopts,
    toolchain_attrs = swift_toolchain_attrs,
)
