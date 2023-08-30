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

load(
    ":actions.bzl",
    "is_action_enabled",
    "run_toolchain_action",
    "swift_action_names",
)
load(":derived_files.bzl", "derived_files")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_DBG",
    "SWIFT_FEATURE_FASTBUILD",
    "SWIFT_FEATURE_NO_EMBED_DEBUG_MODULE",
)
load(":features.bzl", "is_feature_enabled")
load(":toolchain_config.bzl", "swift_toolchain_config")

def ensure_swiftmodule_is_embedded(
        actions,
        feature_configuration,
        label,
        swiftmodule,
        swift_toolchain):
    """Ensures that a `.swiftmodule` file is embedded in a library or binary.

    This function handles the distinctions between how different object file
    formats (i.e., Mach-O vs. ELF) have to embed the module AST for debugging
    purposes.

    Args:
        actions: The object used to register actions.
        feature_configuration: The Swift feature configuration.
        label: The `Label` of the target being built.
        swiftmodule: The `.swiftmodule` file to be wrapped.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.

    Returns:
        A `LinkerInput` containing any flags and/or input files that should be
        propagated to the linker to embed the `.swiftmodule` as debugging
        information in the binary.
    """
    if is_action_enabled(
        action_name = swift_action_names.MODULEWRAP,
        swift_toolchain = swift_toolchain,
    ):
        # For ELF-format binaries, we need to invoke a Swift modulewrap action
        # to wrap the .swiftmodule file in a .o file that gets propagated to the
        # linker.
        modulewrap_obj = derived_files.modulewrap_object(
            actions,
            target_name = label.name,
        )
        _register_modulewrap_action(
            actions = actions,
            feature_configuration = feature_configuration,
            object = modulewrap_obj,
            swiftmodule = swiftmodule,
            swift_toolchain = swift_toolchain,
        )

        # Passing the `.o` file directly to the linker ensures that it links to
        # the binary even if nothing else references it.
        return cc_common.create_linker_input(
            additional_inputs = depset([modulewrap_obj]),
            owner = label,
            user_link_flags = depset([modulewrap_obj.path]),
        )

    # If module-wrapping is not enabled for the toolchain, assume that we can
    # use the `-add_ast_path` linker flag.
    return cc_common.create_linker_input(
        owner = label,
        user_link_flags = depset([
            "-Wl,-add_ast_path,{}".format(swiftmodule.path),
        ]),
        additional_inputs = depset([swiftmodule]),
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

def should_embed_swiftmodule_for_debugging(
        feature_configuration,
        module_context):
    """Returns True if the configuration wants modules embedded for debugging.

    Args:
        feature_configuration: The Swift feature configuration.
        module_context: The module context returned by `swift_common.compile`.

    Returns:
        True if the `.swiftmodule` should be embedded by the linker for
        debugging.
    """
    return (
        module_context.swift and
        module_context.swift.swiftmodule and
        _is_debugging(feature_configuration = feature_configuration) and
        not is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_NO_EMBED_DEBUG_MODULE,
        )
    )

def _is_debugging(feature_configuration):
    """Returns `True` if the current compilation mode produces debug info.

    We replicate the behavior of the C++ build rules for Swift, which are
    described here:
    https://docs.bazel.build/versions/master/user-manual.html#flag--compilation_mode

    Args:
        feature_configuration: The feature configuration.

    Returns:
        `True` if the current compilation mode produces debug info.
    """
    return (
        is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_DBG,
        ) or is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_FASTBUILD,
        )
    )

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
        progress_message = "Wrapping Swift module %{label} for debugging",
        swift_toolchain = swift_toolchain,
    )
