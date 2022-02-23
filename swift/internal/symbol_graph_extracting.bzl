# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Functions relating to symbol graph extraction."""

load(":actions.bzl", "run_toolchain_action", "swift_action_names")
load(":providers.bzl", "create_swift_info")
load(":toolchain_config.bzl", "swift_toolchain_config")
load(":utils.bzl", "merge_compilation_contexts")

def symbol_graph_action_configs():
    """Returns the list of action configs needed to extract symbol graphs.

    If a toolchain supports symbol graph extraction, it should add these to its
    list of action configs so that those actions will be correctly configured.
    (Other required configuration is provided by `compile_action_configs`.)

    Returns:
        The list of action configs needed to extract symbol graphs.
    """
    return [
        swift_toolchain_config.action_config(
            actions = [swift_action_names.SYMBOL_GRAPH_EXTRACT],
            configurators = [
                _symbol_graph_minimum_access_level_configurator,
            ],
        ),
        swift_toolchain_config.action_config(
            actions = [swift_action_names.SYMBOL_GRAPH_EXTRACT],
            configurators = [
                _symbol_graph_output_configurator,
            ],
        ),
    ]

def _symbol_graph_minimum_access_level_configurator(prerequisites, args):
    """Configures the minimum access level of the symbol graph extraction."""
    if prerequisites.minimum_access_level:
        args.add("-minimum-access-level", prerequisites.minimum_access_level)

def _symbol_graph_output_configurator(prerequisites, args):
    """Configures the outputs of the symbol graph extract action."""
    args.add("-output-dir", prerequisites.output_dir.path)

def extract_symbol_graph(
        *,
        actions,
        compilation_contexts,
        feature_configuration,
        minimum_access_level = None,
        module_name,
        output_dir,
        swift_infos,
        swift_toolchain):
    """Extracts the symbol graph from a Swift module.

    Args:
        actions: The object used to register actions.
        compilation_contexts: A list of `CcCompilationContext`s that represent
            C/Objective-C requirements of the target being compiled, such as
            Swift-compatible preprocessor defines, header search paths, and so
            forth. These are typically retrieved from the `CcInfo` providers of
            a target's dependencies.
        feature_configuration: The Swift feature configuration.
        minimum_access_level: The minimum access level of the declarations that
            should be extracted into the symbol graphs. The default value is
            `None`, which means the Swift compiler's default behavior should be
            used (at the time of this writing, the default behavior is
            "public").
        module_name: The name of the module whose symbol graph should be
            extracted.
        output_dir: A directory-type `File` into which `.symbols.json` files
            representing the module's symbol graph will be extracted. If
            extraction is successful, this directory will contain a file named
            `${MODULE_NAME}.symbols.json`. Optionally, if the module contains
            extensions to types in other modules, then there will also be files
            named `${MODULE_NAME}@${EXTENDED_MODULE}.symbols.json`.
        swift_infos: A list of `SwiftInfo` providers from dependencies of the
            target being compiled. This should include both propagated and
            non-propagated (implementation-only) dependencies.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    merged_compilation_context = merge_compilation_contexts(
        transitive_compilation_contexts = compilation_contexts + [
            cc_info.compilation_context
            for cc_info in swift_toolchain.implicit_deps_providers.cc_infos
        ],
    )
    merged_swift_info = create_swift_info(
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
        minimum_access_level = minimum_access_level,
        module_name = module_name,
        output_dir = output_dir,
        transitive_modules = transitive_modules,
        transitive_swiftmodules = transitive_swiftmodules,
    )

    run_toolchain_action(
        actions = actions,
        action_name = swift_action_names.SYMBOL_GRAPH_EXTRACT,
        feature_configuration = feature_configuration,
        outputs = [output_dir],
        prerequisites = prerequisites,
        progress_message = (
            "Extracting symbol graph for {}".format(module_name)
        ),
        swift_toolchain = swift_toolchain,
    )
