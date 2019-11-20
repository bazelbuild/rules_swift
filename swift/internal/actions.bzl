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
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:types.bzl", "types")

def _get_swift_driver_mode_args(driver_mode, swift_toolchain):
    """Gets the arguments to pass to the worker to invoke the Swift driver.

    Args:
        driver_mode: The mode in which to invoke the Swift driver. In other
            words, this is the name of the executable of symlink that you want
            to execute (e.g., `swift`, `swiftc`, `swift-autolink-extract`).
        swift_toolchain: The Swift toolchain being used to register actions.

    Returns:
        A list of values that can be added to an `Args` object and passed to the
        worker to invoke the command.

        This method implements three kinds of "dispatch":

        1.  If the toolchain provides a custom driver executable, it is invoked
            with the requested mode passed via the `--driver_mode` argument.
        2.  If the toolchain provides a root directory, then the returned list
            will be the path to the executable with the same name as the driver
            mode in the `bin` directory of that toolchain.
        3.  If the toolchain does not provide a root, then it is assumed that
            the tool will be available by invoking just the driver mode by name
            (e.g., found on the system path or by another delegating tool like
            `xcrun` from Xcode).
    """
    if swift_toolchain.swift_executable:
        return [
            swift_toolchain.swift_executable,
            "--driver-mode={}".format(driver_mode),
        ]

    if swift_toolchain.root_dir:
        return [paths.join(swift_toolchain.root_dir, "bin", driver_mode)]

    return [driver_mode]

def run_swift_action(
        actions,
        arguments,
        driver_mode,
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

    Args:
        actions: The `Actions` object with which to register actions.
        arguments: The arguments to pass to the invoked action.
        driver_mode: The mode in which to invoke the Swift driver. In other
            words, this is the name of the executable of symlink that you want
            to execute (e.g., `swift`, `swiftc`, `swift-autolink-extract`).
        swift_toolchain: The Swift toolchain being used to register actions.
        **kwargs: Additional arguments to `actions.run`.
    """
    if "executable" in kwargs:
        fail("run_swift_action does not support 'executable'. " +
             "Use 'driver_mode' instead.")

    remaining_args = dict(kwargs)

    # Note that we add the toolchain values second; we do not want the caller to
    # ever be able to override those values.
    env = dicts.add(
        remaining_args.pop("env", None) or {},
        swift_toolchain.action_environment or {},
    )
    execution_requirements = dicts.add(
        remaining_args.pop("execution_requirements", None) or {},
        swift_toolchain.execution_requirements or {},
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
    driver_mode_args.add_all(_get_swift_driver_mode_args(
        driver_mode = driver_mode,
        swift_toolchain = swift_toolchain,
    ))

    actions.run(
        arguments = [driver_mode_args] + arguments,
        env = env,
        executable = swift_toolchain.swift_worker,
        execution_requirements = execution_requirements,
        tools = tools,
        **remaining_args
    )
