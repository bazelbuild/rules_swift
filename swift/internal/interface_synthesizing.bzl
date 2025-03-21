# Copyright 2025 The Bazel Authors. All rights reserved.
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

"""Functions relating to synthesizing Swift interfaces from non-Swift targets."""

load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo")
load(":action_names.bzl", "SWIFT_ACTION_SYNTHESIZE_INTERFACE")
load(":actions.bzl", "run_toolchain_action")
load(":toolchain_utils.bzl", "SWIFT_TOOLCHAIN_TYPE")
load(":utils.bzl", "merge_compilation_contexts")

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def synthesize_interface(
        *,
        actions,
        compilation_contexts,
        feature_configuration,
        module_name,
        output_file,
        swift_infos,
        swift_toolchain,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE):
    """Extracts the symbol graph from a Swift module.

    Args:
        actions: The object used to register actions.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        feature_configuration: The Swift feature configuration.
        module_name: The name of the module whose symbol graph should be
            extracted.
        output_file: A `File` into which the synthesized interface will be
            written.
        swift_infos: A list of `SwiftInfo` providers from dependencies of the
            target being compiled. This should include both propagated and
            non-propagated (implementation-only) dependencies.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        toolchain_type: The toolchain type of the `swift_toolchain` which is
            used for the proper selection of the execution platform inside
            `run_toolchain_action`.
    """
    merged_compilation_context = merge_compilation_contexts(
        transitive_compilation_contexts = compilation_contexts + [
            cc_info.compilation_context
            for cc_info in swift_toolchain.implicit_deps_providers.cc_infos
        ],
    )
    merged_swift_info = SwiftInfo(
        swift_infos = (
            swift_infos + swift_toolchain.implicit_deps_providers.swift_infos
        ),
    )

    # Flattening this `depset` is necessary because we need to extract the
    # module maps or precompiled modules out of structured values and do so
    # conditionally.
    transitive_modules = merged_swift_info.transitive_modules.to_list()

    transitive_swiftmodules = []
    for module in transitive_modules:
        swift_module = module.swift
        if swift_module:
            transitive_swiftmodules.append(swift_module.swiftmodule)

    prerequisites = struct(
        bin_dir = feature_configuration._bin_dir,
        cc_compilation_context = merged_compilation_context,
        genfiles_dir = feature_configuration._genfiles_dir,
        is_swift = True,
        module_name = module_name,
        output_file = output_file,
        target_label = feature_configuration._label,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
    )

    run_toolchain_action(
        actions = actions,
        action_name = SWIFT_ACTION_SYNTHESIZE_INTERFACE,
        feature_configuration = feature_configuration,
        outputs = [output_file],
        prerequisites = prerequisites,
        progress_message = (
            "Synthesizing Swift interface for {}".format(module_name)
        ),
        swift_toolchain = swift_toolchain,
        toolchain_type = toolchain_type,
    )
