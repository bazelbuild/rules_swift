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

"""Functions dealing with basic action registration.

The functions in this file are meant to hide the implementation detail of the
partials from callers who simply want to register toolchain actions, both
externally and in the rule implementations themselves.
"""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:types.bzl", "types")

def run_toolchain_action(actions, toolchain, **kwargs):
    """Equivalent to `actions.run`, but respecting toolchain settings.

    This function applies the toolchain's environment and execution requirements and also wraps the
    command in a wrapper executable if the toolchain requires it (for example, `xcrun` on Darwin).

    If the `executable` argument is a simple basename and the toolchain has an explicit root
    directory, then it is modified to be relative to the toolchain's `bin` directory. Otherwise,
    if it is an absolute path, a relative path with multiple path components, or a `File` object,
    then it is executed as-is.

    Args:
      actions: The `Actions` object with which to register actions.
      toolchain: The `SwiftToolchainInfo` provider that prescribes the action's requirements.
      **kwargs: Additional arguments to `actions.run`.
    """
    modified_args = dict(kwargs)

    executable = modified_args.get("executable")
    if (types.is_string(executable) and "/" not in executable and toolchain.root_dir):
        modified_args["executable"] = paths.join(toolchain.root_dir, "bin", executable)

    partial.call(toolchain.action_registrars.run, actions, **modified_args)

def run_toolchain_shell_action(actions, toolchain, **kwargs):
    """Equivalent to `actions.run_shell`, but respecting toolchain settings.

    This function applies the toolchain's environment and execution requirements and also wraps the
    command in a wrapper executable if the toolchain requires it (for example, `xcrun` on Darwin).

    Args:
      actions: The `Actions` object with which to register actions.
      toolchain: The `SwiftToolchainInfo` provider that prescribes the action's
          requirements.
      **kwargs: Additional arguments to `actions.run_shell`.
    """
    partial.call(toolchain.action_registrars.run_shell, actions, **kwargs)

def run_toolchain_swift_action(actions, swift_tool, toolchain, **kwargs):
    """Executes a Swift toolchain tool using its wrapper.

    This function applies the toolchain's environment and execution requirements and wraps the
    command in a toolchain-specific wrapper if necessary (for example, `xcrun` on Darwin) and in
    additional pre- and post-processing to handle certain tasks like debug prefix remapping and
    module cache health.

    If the `swift_tool` argument is a simple basename and the toolchain has an explicit root
    directory, then it is modified to be relative to the toolchain's `bin` directory. Otherwise,
    if it is an absolute path, a relative path with multiple path components, or a `File` object,
    then it is executed as-is.

    Args:
      actions: The `Actions` object with which to register actions.
      swift_tool: The name of the Swift tool to invoke.
      toolchain: The `SwiftToolchainInfo` provider that prescribes the action's requirements.
      **kwargs: Additional arguments to `actions.run`.
    """
    if "executable" in kwargs:
        fail("run_toolchain_swift_action does not support 'executable'. " +
             "Use 'swift_tool' instead.")

    modified_args = dict(kwargs)

    if ("/" not in swift_tool and toolchain.root_dir):
        modified_args["swift_tool"] = paths.join(toolchain.root_dir, "bin", swift_tool)
    else:
        modified_args["swift_tool"] = swift_tool

    partial.call(toolchain.action_registrars.run_swift, actions, **modified_args)
