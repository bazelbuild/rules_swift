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
"""

load(
    "@build_bazel_rules_swift//swift/internal:compiling.bzl",
    "compile",
    "compile_module_interface",
    "precompile_clang_module",
)
load(
    "@build_bazel_rules_swift//swift/internal:features.bzl",
    "configure_features",
    "get_cc_feature_configuration",
    "is_feature_enabled",
)
load(
    "@build_bazel_rules_swift//swift/internal:linking.bzl",
    "create_linking_context_from_compilation_outputs",
)
load(
    "@build_bazel_rules_swift//swift/internal:symbol_graph_extracting.bzl",
    "extract_symbol_graph",
)
load(
    "@build_bazel_rules_swift//swift/internal:transitions.bzl",
    "cxx_interop_transition",
)
load(
    "@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl",
    "get_swift_toolchain",
    "use_swift_toolchain",
)

visibility("public")

# The exported `swift_common` module, which defines the public API for directly
# invoking actions that compile Swift code from other rules.
swift_common = struct(
    cc_feature_configuration = get_cc_feature_configuration,
    compile = compile,
    compile_module_interface = compile_module_interface,
    configure_features = configure_features,
    create_linking_context_from_compilation_outputs = create_linking_context_from_compilation_outputs,
    cxx_interop_transition = cxx_interop_transition,
    extract_symbol_graph = extract_symbol_graph,
    get_toolchain = get_swift_toolchain,
    is_enabled = is_feature_enabled,
    precompile_clang_module = precompile_clang_module,
    use_toolchain = use_swift_toolchain,
)
