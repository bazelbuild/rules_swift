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

"""Functions relating to debugging support during compilation and linking."""

load(":actions.bzl", "run_toolchain_action", "swift_action_names")
load(":derived_files.bzl", "derived_files")
load(":toolchain_config.bzl", "swift_toolchain_config")

def ensure_swiftmodule_is_embedded(
        actions,
        feature_configuration,
        swiftmodule,
        target_name,
        swift_toolchain):
    """Ensures that a `.swiftmodule` file is embedded in a library or binary.

    This function handles the distinctions between how different object file
    formats (i.e., Mach-O vs. ELF) have to embed the module AST for debugging
    purposes.

    Args:
        actions: The object used to register actions.
        feature_configuration: The Swift feature configuration.
        swiftmodule: The `.swiftmodule` file to be wrapped.
        target_name: The name of the target being built.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.

    Returns:
      A `struct` containing three fields:

      *   `linker_flags`: A list of additional flags that should be propagated
          to the linker.
      *   `linker_inputs`: A list of additional inputs that are not necessarily
          object files, but which are referenced in `linker_flags` and should
          therefore be passed to the linker.
      *   `objects_to_link`: A list of `.o` files that should be included in the
          static archive or binary that represents the module.
    """
    linker_flags = []
    linker_inputs = []
    objects_to_link = []

    if swift_toolchain.object_format == "elf":
        # For ELF-format binaries, we need to invoke a Swift modulewrap action
        # to wrap the .swiftmodule file in a .o file that gets propagated to the
        # linker.
        modulewrap_obj = derived_files.modulewrap_object(
            actions,
            target_name = target_name,
        )
        objects_to_link.append(modulewrap_obj)

        _register_modulewrap_action(
            actions = actions,
            feature_configuration = feature_configuration,
            object = modulewrap_obj,
            swiftmodule = swiftmodule,
            swift_toolchain = swift_toolchain,
        )
    elif swift_toolchain.object_format == "macho":
        linker_flags.append("-Wl,-add_ast_path,{}".format(swiftmodule.path))
        linker_inputs.append(swiftmodule)
    else:
        fail("Internal error: Unexpected object format '{}'.".format(
            swift_toolchain.object_format,
        ))

    return struct(
        linker_flags = linker_flags,
        linker_inputs = linker_inputs,
        objects_to_link = objects_to_link,
    )

def modulewrap_action_configs():
    """Returns the list of action configs needed to perform module wrapping.

    If a toolchain supports module wrapping, it should add these to its list of
    action configs so that those actions will be correctly configured.

    Returns:
        The list of action configs needed to perform module wrapping.
    """
    return [
        swift_toolchain_config.action_config(
            actions = [swift_action_names.MODULEWRAP],
            configurators = [
                _modulewrap_input_configurator,
                _modulewrap_output_configurator,
            ],
        ),
    ]

def _modulewrap_input_configurator(prerequisites, args):
    """Configures the inputs of the modulewrap action."""
    swiftmodule_file = prerequisites.swiftmodule_file

    args.add(swiftmodule_file)
    return swift_toolchain_config.config_result(inputs = [swiftmodule_file])

def _modulewrap_output_configurator(prerequisites, args):
    """Configures the outputs of the modulewrap action."""
    args.add("-o", prerequisites.object_file)

def _register_modulewrap_action(
        actions,
        feature_configuration,
        object,
        swiftmodule,
        swift_toolchain):
    """Wraps a Swift module in a `.o` file that can be linked into a binary.

    This step (invoking `swift -modulewrap`) is required for the `.swiftmodule`
    of the main module of an executable on platforms with ELF-format object
    files; otherwise, debuggers will not be able to see those symbols.

    Args:
        actions: The object used to register actions.
        feature_configuration: The Swift feature configuration.
        object: The object file that will be produced by the modulewrap task.
        swiftmodule: The `.swiftmodule` file to be wrapped.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    prerequisites = struct(
        object_file = object,
        swiftmodule_file = swiftmodule,
    )
    run_toolchain_action(
        actions = actions,
        action_name = swift_action_names.MODULEWRAP,
        feature_configuration = feature_configuration,
        outputs = [object],
        prerequisites = prerequisites,
        progress_message = (
            "Wrapping {} for debugging".format(swiftmodule.short_path)
        ),
        swift_toolchain = swift_toolchain,
    )
