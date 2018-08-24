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

def run_toolchain_action(actions, toolchain, **kwargs):
    """Equivalent to `actions.run`, but for tools in the Swift toolchain.

    This function applies the toolchain's environment and execution requirements
    and also wraps the command in a wrapper executable if the toolchain requires
    it (for example, `xcrun` on Darwin).

    If the `executable` argument is a simple basename (such as "swiftc") and the
    toolchain has an explicit root directory, then it is modified to be relative
    to the toolchain's `bin` directory. Otherwise, if it is an absolute path, a
    relative path with multiple path components, or a `File` object, then it is
    executed as-is.

    Args:
      actions: The `Actions` object with which to register actions.
      toolchain: The `SwiftToolchainInfo` provider that prescribes the action's
          requirements.
      **kwargs: Additional arguments to `actions.run`.
    """
    modified_args = dict(kwargs)

    executable = modified_args.get("executable")
    if (type(executable) == type("") and "/" not in executable and
        toolchain.root_dir):
        modified_args["executable"] = paths.join(
            toolchain.root_dir,
            "bin",
            executable,
        )

    partial.call(toolchain.action_registrars.run, actions, **modified_args)

def run_toolchain_shell_action(actions, toolchain, **kwargs):
    """Equivalent to `actions.run_shell`, but respecting toolchain settings.

    This function applies the toolchain's environment and execution requirements
    and also wraps the command in a wrapper executable if the toolchain requires
    it (for example, `xcrun` on Darwin).

    Args:
      actions: The `Actions` object with which to register actions.
      toolchain: The `SwiftToolchainInfo` provider that prescribes the action's
          requirements.
      **kwargs: Additional arguments to `actions.run_shell`.
    """
    partial.call(toolchain.action_registrars.run_shell, actions, **kwargs)
