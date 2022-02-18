# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Definitions used to configure toolchains and actions."""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:types.bzl", "types")

_ActionConfigInfo = provider(
    doc = "An action configuration in the Swift toolchain.",
    fields = [
        "actions",
        "configurators",
        "features",
        "not_features",
    ],
)

_ConfigResultInfo = provider(
    doc = "The inputs required by an action configurator.",
    fields = [
        "inputs",
        "transitive_inputs",
    ],
)

_ToolConfigInfo = provider(
    doc = "A tool used by the Swift toolchain and its requirements.",
    fields = [
        "args",
        "env",
        "executable",
        "execution_requirements",
        "tool_input_manifests",
        "tool_inputs",
        "use_param_file",
        "worker_mode",
    ],
)

def _normalize_action_config_features(features):
    """Validates and normalizes the `features` of an `action_config`.

    This method validates that the argument is either `None`, a non-empty
    list of strings, or a non-empty list of lists of strings. If the argument is
    the shorthand form (a list of strings), it is normalized by wrapping it in
    an outer list so that action building code does not need to be concerned
    about the distinction.

    Args:
        features: The `features` argument passed to `action_config`.

    Returns:
        The `features` argument, normalized if necessary.
    """
    if features == None:
        return features

    failure_message = (
        "The 'features' argument passed to " +
        "'swift_toolchain_config.action_config' must be either None, a list " +
        "of strings, or a list of lists of strings.",
    )

    # Fail if the argument is not a list, or if it is but it is empty.
    if not types.is_list(features) or not features:
        fail(failure_message)

    outer_list_has_strings = False
    outer_list_has_lists = False

    # Check each element in the list to determine if it is a list of lists
    # or a list of strings.
    for element in features:
        if types.is_list(element):
            outer_list_has_lists = True
        elif types.is_string(element) and element:
            outer_list_has_strings = True
        else:
            fail(failure_message)

    # Forbid mixing lists and strings at the top-level.
    if outer_list_has_strings and outer_list_has_lists:
        fail(failure_message)

    # If the original list was a list of strings, wrap it before returning it
    # to the caller.
    if outer_list_has_strings:
        return [features]

    # Otherwise, return the original list of lists.
    return features

def _action_config(
        actions,
        configurators,
        features = None,
        not_features = None):
    """Returns a new Swift toolchain action configuration.

    This function validates the inputs, causing the build to fail if they have
    incorrect types or are otherwise invalid.

    Args:
        actions: A `list` of strings denoting the names of the actions for
            which the configurators should be invoked.
        configurators: A `list` of functions or Skylib partials that will be
            invoked to add command line arguments and collect inputs for the
            actions. These functions/partials take two arguments---a
            `prerequisites` struct and an `Args` object---and return a `depset`
            of `File`s that should be used as inputs to the action (or `None`
            if the configurator does not add any inputs).
        features: The `list` of features that must be enabled for the
            configurators to be applied to the action. This argument can take
            one of three forms: `None` (the default), in which case the
            configurators are unconditionally applied; a non-empty `list` of
            `list`s of feature names (strings), in which case *all* features
            mentioned in *one* of the inner lists must be enabled; or a single
            non-empty `list` of feature names, which is a shorthand form
            equivalent to that single list wrapped in another list.
        not_features: The `list` of features that must be disabled for the
            configurators to be applied to the action. Like `features`, this
            argument can take one of three forms: `None` (the default), in
            which case the configurators are applied if `features` was
            satisfied; a non-empty `list` of `list`s of feature names (strings),
            in which case *all* features mentioned in *one* of the inner lists
            must be disabled, otherwise the configurators will not be applied,
            even if `features` was satisfied; or a single non-empty `list` of
            feature names, which is a shorthand form equivalent to that single
            list wrapped in another list.

    Returns:
        A validated action configuration.
    """
    return _ActionConfigInfo(
        actions = actions,
        configurators = configurators,
        features = _normalize_action_config_features(features),
        not_features = _normalize_action_config_features(not_features),
    )

def _add_arg_impl(
        arg_name_or_value,
        value,
        _prerequisites,
        args,
        format = None):
    """Implementation function for the `add_arg` convenience configurator.

    Args:
        arg_name_or_value: The `arg_name_or_value` passed to `Args.add`. Bound
            at partial creation time.
        value: The `value` passed to `Args.add`. Bound at partial creation
            time.
        _prerequisites: Unused by this function.
        args: The `Args` object to which flags will be added.
        format: The `format` passed to `Args.add`. Bound at partial creation
            time.
    """

    # `Args.add` doesn't permit the `value` argument to be `None`, only
    # "unbound", so we have to check for this and not pass it *at all* if it
    # wasn't specified when the partial was created.
    if value == None:
        args.add(arg_name_or_value, format = format)
    else:
        args.add(arg_name_or_value, value, format = format)

def _add_arg(arg_name_or_value, value = None, format = None):
    """Returns a configurator that adds a simple argument to the command line.

    This is provided as a convenience for the simple case where a configurator
    wishes to add a flag to the command line, perhaps based on the enablement
    of a feature, without writing a separate function solely for that one flag.

    Args:
        arg_name_or_value: The `arg_name_or_value` argument that will be passed
            to `Args.add`.
        value: The `value` argument that will be passed to `Args.add` (`None`
            by default).
        format: The `format` argument that will be passed to `Args.add` (`None`
            by default).

    Returns:
        A Skylib `partial` that can be added to the `configurators` list of an
        `action_config`.
    """
    return partial.make(
        _add_arg_impl,
        arg_name_or_value,
        value,
        format = format,
    )

def _config_result(inputs = [], transitive_inputs = []):
    """Returns a value that can be returned from an action configurator.

    Args:
        inputs: A list of `File`s that should be passed as inputs to the action
            being configured.
        transitive_inputs: A list of `depset`s of `File`s that should be passed
            as inputs to the action being configured.

    Returns:
        A new config result that can be returned from a configurator.
    """
    return _ConfigResultInfo(
        inputs = inputs,
        transitive_inputs = transitive_inputs,
    )

def _driver_tool_config(
        driver_mode,
        args = [],
        swift_executable = None,
        toolchain_root = None,
        **kwargs):
    """Returns a new Swift toolchain tool configuration for the Swift driver.

    This is a convenience function that supports the various ways that the Swift
    driver can have its location specified or overridden by the build rules,
    such as by providing a toolchain root directory or a custom executable. It
    supports three kinds of "dispatch":

    1.  If the toolchain provides a custom driver executable, the returned tool
        config invokes it with the requested mode passed via the `--driver_mode`
        argument.
    2.  If the toolchain provides a root directory, then the returned tool
        config will use an executable that is a string with the same name as the
        driver mode in the `bin` directory of that toolchain.
    3.  If the toolchain does not provide a root, then the returned tool config
        simply uses the driver mode as the executable, assuming that it will be
        available by invoking that alone (e.g., it will be found on the system
        path or by another delegating tool like `xcrun` from Xcode).

    Args:
        driver_mode: The mode in which to invoke the Swift driver. In other
            words, this is the name of the executable of symlink that you want
            to execute (e.g., `swift`, `swiftc`, `swift-autolink-extract`).
        args: A list of arguments that are always passed to the driver.
        swift_executable: A custom Swift driver executable, if provided by the
            toolchain.
        toolchain_root: The root directory of the Swift toolchain, if the
            toolchain provides it.
        **kwargs: Additional arguments that will be passed unmodified to
            `swift_toolchain_config.tool_config`.

    Returns:
        A new tool configuration.
    """
    if swift_executable:
        executable = swift_executable
        args = ["--driver-mode={}".format(driver_mode)] + args
    elif toolchain_root:
        executable = paths.join(toolchain_root, "bin", driver_mode)
    else:
        executable = driver_mode

    return _tool_config(args = args, executable = executable, **kwargs)

def _validate_worker_mode(worker_mode):
    """Validates the `worker_mode` argument of `tool_config`.

    This function fails the build if the worker mode is not None, "persistent",
    or "wrap".

    Args:
        worker_mode: The worker mode to validate.

    Returns:
        The original worker mode, if it was valid.
    """
    if worker_mode != None and worker_mode not in ("persistent", "wrap"):
        fail(
            "The 'worker_mode' argument of " +
            "'swift_toolchain_config.tool_config' must be either None, " +
            "'persistent', or 'wrap'.",
        )

    return worker_mode

def _tool_config(
        executable,
        args = [],
        env = {},
        execution_requirements = {},
        tool_input_manifests = [],
        tool_inputs = depset(),
        use_param_file = False,
        worker_mode = None):
    """Returns a new Swift toolchain tool configuration.

    Args:
        executable: The `File` or `string` denoting the tool that should be
            executed. This will be used as the `executable` argument of spawned
            actions unless `worker_mode` is set, in which case it will be used
            as the first argument to the worker.
        args: A list of arguments that are always passed to the tool.
        env: A dictionary of environment variables that should be set when
            invoking actions using this tool.
        execution_requirements: A dictionary of execution requirements that
            should be passed when creating actions with this tool.
        tool_input_manifests: A list of input runfiles metadata for tools that
            should be passed into the `input_manifests` argument of the
            `ctx.actions.run` call that registers actions using this tool (see
            also Bazel's `ctx.resolve_tools`).
        tool_inputs: A `depset` of additional inputs for tools that should be
            passed into the `tools` argument of the `ctx.actions.run` call that
            registers actions using this tool (see also Bazel's
            `ctx.resolve_tools`).
        use_param_file: If True, actions invoked using this tool will have their
            arguments written to a param file.
        worker_mode: A string, or `None`, describing how the tool is invoked
            using the build rules' worker, if at all. If `None`, the tool will
            be invoked directly. If `"wrap"`, the tool will be wrapped in an
            invocation of the worker but otherwise run as a single process. If
            `"persistent"`, then the action will be launched with execution
            requirements that indicate that Bazel should attempt to use a
            persistent worker if the spawn strategy allows for it (starting a
            new instance if necessary, or connecting to an existing one).

    Returns:
        A new tool configuration.
    """
    return _ToolConfigInfo(
        args = args,
        env = env,
        executable = executable,
        execution_requirements = execution_requirements,
        tool_input_manifests = tool_input_manifests,
        tool_inputs = tool_inputs,
        use_param_file = use_param_file,
        worker_mode = _validate_worker_mode(worker_mode),
    )

swift_toolchain_config = struct(
    action_config = _action_config,
    add_arg = _add_arg,
    config_result = _config_result,
    driver_tool_config = _driver_tool_config,
    tool_config = _tool_config,
)
