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

def get_swift_tool(swift_toolchain, tool):
    """Gets the path to the given Swift toolchain tool.

    Args:
        swift_toolchain: The Swift toolchain being used to register actions.
        tool: The name of a tool in the Swift toolchain (i.e., in the `bin` directory).

    Returns:
        The path to the tool. If the toolchain provides a root directory, then the path will
        include the `bin` directory of that toolchain. If the toolchain does not provide a root,
        then it is assumed that the tool will be available by invoking just its name (e.g., found
        on the system path or by another delegating tool like `xcrun` from Xcode).
    """
    if ("/" not in tool and swift_toolchain.root_dir):
        return paths.join(swift_toolchain.root_dir, "bin", tool)
    return tool

def run_swift_action(actions, swift_toolchain, **kwargs):
    """Executes a Swift toolchain tool using the worker.

    This function applies the toolchain's environment and execution requirements and wraps the
    invocation in the worker tool that handles platform-specific requirements (for example, `xcrun`
    on Darwin) and in additional pre- and post-processing to handle certain tasks like debug prefix
    remapping and module cache health.

    Since this function uses the worker as the `executable` of the underlying action, it is an
    error to pass `executable` into this function. Instead, the tool to run should be the first
    item in the `arguments` list (or in the first `Args` object). This tool should be obtained
    using `get_swift_tool` in order to correctly handle toolchains with explicit root directories.

    Args:
      actions: The `Actions` object with which to register actions.
      swift_toolchain: The Swift toolchain being used to register actions.
      **kwargs: Additional arguments to `actions.run`.
    """
    if "executable" in kwargs:
        fail("run_swift_action does not support 'executable'. " +
             "The tool to run should be the first item in 'arguments'.")

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

    actions.run(
        env = env,
        executable = swift_toolchain.swift_worker,
        execution_requirements = execution_requirements,
        tools = tools,
        **remaining_args
    )
