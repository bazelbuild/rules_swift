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

"""Functions for registering actions that invoke Swift tools."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:types.bzl", "types")
load(":features.bzl", "are_all_features_enabled")
load(":toolchain_config.bzl", "swift_toolchain_config")

# The names of actions currently supported by the Swift build rules.
swift_action_names = struct(
    # Extracts a linker input file containing libraries to link from a compiled
    # object file to provide autolink functionality based on `import` directives
    # on ELF platforms.
    AUTOLINK_EXTRACT = "SwiftAutolinkExtract",

    # Compiles one or more `.swift` source files into a `.swiftmodule` and
    # object files.
    COMPILE = "SwiftCompile",

    # Wraps a `.swiftmodule` in a `.o` file on ELF platforms so that it can be
    # linked into a binary for debugging.
    MODULEWRAP = "SwiftModuleWrap",
)

def _apply_configurator(configurator, prerequisites, args):
    """Calls an action configurator with the given arguments.

    This function appropriately handles whether the configurator is a Skylib
    partial or a plain function.

    Args:
        configurator: The action configurator to call.
        prerequisites: The prerequisites struct that the configurator may use
            to control its behavior.
        args: The `Args` object to which the configurator will add command line
            arguments for the tool being invoked.

    Returns:
        The `swift_toolchain_config.config_result` value, or `None`, that was
        returned by the configurator.
    """
    if types.is_function(configurator):
        return configurator(prerequisites, args)
    else:
        return partial.call(configurator, prerequisites, args)

def apply_action_configs(
        action_name,
        args,
        feature_configuration,
        prerequisites,
        swift_toolchain):
    """Applies the action configs for the given action.

    TODO(b/147091143): Make this function private after the compilation actions
    have been migrated to `run_toolchain_action`.

    Args:
        action_name: The name of the action that should be run.
        args: The `Args` object to which command line flags will be added.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        prerequisites: An action-specific `struct` whose fields can be accessed
            by the action configurators to add files and other dependent data to
            the command line.
        swift_toolchain: The Swift toolchain being used to build.

    Returns:
        A `swift_toolchain_config.action_inputs` value that contains the files
        that are required inputs of the action, as determined by the
        configurators.
    """
    inputs = []
    transitive_inputs = []

    for action_config in swift_toolchain.action_configs:
        # Skip the action config if it does not apply to the requested action.
        if action_name not in action_config.actions:
            continue

        if action_config.features == None:
            # If the feature list was `None`, unconditionally apply the
            # configurators.
            should_apply_configurators = True
        else:
            # Check each of the feature lists to determine if any of them has
            # all of its features satisfied by the feature configuration.
            should_apply_configurators = False
            for feature_names in action_config.features:
                if are_all_features_enabled(
                    feature_configuration = feature_configuration,
                    feature_names = feature_names,
                ):
                    should_apply_configurators = True
                    break

        # If one of the feature lists is completely satisfied, invoke the
        # configurators.
        if should_apply_configurators:
            for configurator in action_config.configurators:
                action_inputs = _apply_configurator(
                    configurator,
                    prerequisites,
                    args,
                )
                if action_inputs:
                    inputs.extend(action_inputs.inputs)
                    transitive_inputs.extend(action_inputs.transitive_inputs)

    # Merge the action results into a single result that we return.
    return swift_toolchain_config.config_result(
        inputs = inputs,
        transitive_inputs = transitive_inputs,
    )

def is_action_enabled(action_name, swift_toolchain):
    """Returns True if the given action is enabled in the Swift toolchain.

    Args:
        action_name: The name of the action.
        swift_toolchain: The Swift toolchain being used to build.

    Returns:
        True if the action is enabled, or False if it is not.
    """
    tool_config = swift_toolchain.tool_configs.get(action_name)
    return bool(tool_config)

def run_swift_action(
        actions,
        action_name,
        arguments,
        swift_toolchain,
        **kwargs):
    """Executes the Swift driver using the worker.

    This function applies the toolchain's environment and execution requirements
    and wraps the invocation in the worker tool that handles platform-specific
    requirements (for example, `xcrun` on Darwin) and in additional pre- and
    post-processing to handle certain tasks like debug prefix remapping and
    module cache health.

    Since this function uses the worker as the `executable` of the underlying
    action, it is an error to pass `executable` into this function. Instead, the
    `driver_mode` argument should be used to specify which Swift tool should be
    invoked (`swift`, `swiftc`, `swift-autolink-extract`, etc.). This lets the
    rules correctly handle the case where a custom driver executable is provided
    by passing the `--driver-mode` flag that overrides its internal `argv[0]`
    handling.

    TODO(b/147091143): Remove this once all actions have migrated off of it.

    Args:
        actions: The `Actions` object with which to register actions.
        action_name: The name of the toolchain action to run. This is used to
            retrieve the configured tool's environment and execution
            requirements during the migration phase.
        arguments: The arguments to pass to the invoked action.
        swift_toolchain: The Swift toolchain being used to register actions.
        **kwargs: Additional arguments to `actions.run`.
    """
    if "executable" in kwargs:
        fail("run_swift_action does not support 'executable'. " +
             "Use 'driver_mode' instead.")

    remaining_args = dict(kwargs)

    # Note that we add the toolchain values second; we do not want the caller to
    # ever be able to override those values.
    tool_config = swift_toolchain.tool_configs.get(action_name)
    env = dicts.add(remaining_args.pop("env", None) or {}, tool_config.env)
    execution_requirements = dicts.add(
        remaining_args.pop("execution_requirements", None) or {},
        tool_config.execution_requirements,
    )

    # Add the toolchain's files to the `tools` argument of the action.
    user_tools = remaining_args.pop("tools", None)
    toolchain_files = swift_toolchain.all_files
    if types.is_list(user_tools):
        tools = depset(user_tools, transitive = [toolchain_files])
    elif type(user_tools) == type(depset()):
        tools = depset(transitive = [user_tools, toolchain_files])
    elif user_tools:
        fail("'tools' argument must be a sequence or depset.")
    else:
        tools = toolchain_files

    driver_mode_args = actions.args()
    driver_mode_args.add(tool_config.executable)
    driver_mode_args.add_all(tool_config.args)

    actions.run(
        arguments = [driver_mode_args] + arguments,
        env = env,
        executable = swift_toolchain.swift_worker,
        execution_requirements = execution_requirements,
        tools = tools,
        **remaining_args
    )

def run_toolchain_action(
        actions,
        action_name,
        feature_configuration,
        prerequisites,
        swift_toolchain,
        mnemonic = None,
        **kwargs):
    """Runs an action using the toolchain's tool and action configurations.

    Args:
        actions: The rule context's `Actions` object, which will be used to
            create `Args` objects.
        action_name: The name of the action that should be run.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        mnemonic: The mnemonic to associate with the action. If not provided,
            the action name itself will be used.
        prerequisites: An action-specific `struct` whose fields can be accessed
            by the action configurators to add files and other dependent data to
            the command line.
        swift_toolchain: The Swift toolchain being used to build.
        **kwargs: Additional arguments passed directly to `actions.run`.
    """
    tool_config = swift_toolchain.tool_configs.get(action_name)
    if not tool_config:
        fail(
            "There is no tool configured for the action " +
            "'{}' in this toolchain. If this action is ".format(action_name) +
            "supported conditionally, you must call 'is_action_enabled' " +
            "before attempting to register it.",
        )

    args = actions.args()
    if tool_config.use_param_file:
        args.set_param_file_format("multiline")
        args.use_param_file("@%s", use_always = True)

    execution_requirements = dict(tool_config.execution_requirements)

    # If the tool configuration says to use the worker process, then use the
    # worker as the actual executable and pass the tool as the first argument
    # (and as a tool input). Otherwise, just use the tool as the executable
    # directly.
    tools = []
    if tool_config.worker_mode:
        # Only enable persistent workers if the toolchain supports response
        # files, because the worker unconditionally writes its arguments into
        # one to prevent command line overflow in this mode.
        if (
            tool_config.worker_mode == "persistent" and
            tool_config.use_param_file
        ):
            execution_requirements["supports-workers"] = 1

        executable = swift_toolchain.swift_worker
        args.add(tool_config.executable)
        if not types.is_string(tool_config.executable):
            tools.append(tool_config.executable)
    else:
        executable = tool_config.executable
    tools.extend(tool_config.additional_tools)

    # If the tool configuration has any required arguments, add those first.
    if tool_config.args:
        args.add_all(tool_config.args)

    # Apply the action configs that are relevant based on the requested action
    # and feature configuration, to populate the `Args` object and collect the
    # required inputs.
    action_inputs = apply_action_configs(
        action_name = action_name,
        args = args,
        feature_configuration = feature_configuration,
        prerequisites = prerequisites,
        swift_toolchain = swift_toolchain,
    )

    actions.run(
        arguments = [args],
        env = tool_config.env,
        executable = executable,
        execution_requirements = execution_requirements,
        inputs = depset(
            action_inputs.inputs,
            transitive = action_inputs.transitive_inputs,
        ),
        mnemonic = mnemonic if mnemonic else action_name,
        tools = tools,
        **kwargs
    )
