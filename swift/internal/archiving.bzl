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

"""Implementation of static library archiving logic for Swift."""

load(":actions.bzl", "run_toolchain_action")

def register_static_archive_action(
        actions,
        ar_executable,
        output,
        toolchain,
        mnemonic = "Archive",
        objects = [],
        progress_message = None):
    """Registers actions that create a static archive.

    Args:
      actions: The object used to register actions.
      ar_executable: The path to the `ar` executable to use when creating the
          archive, if it should be used.
      output: A `File` to which the output archive will be written.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      mnemonic: The mnemonic to display when the action is executed.
      objects: A list of `File`s denoting object (.o) files that will be merged
          into the archive.
      progress_message: The progress message to display when the action is
          executed.
    """
    if ar_executable:
        _register_ar_action(
            actions = actions,
            ar_executable = ar_executable,
            mnemonic = mnemonic,
            objects = objects,
            output = output,
            progress_message = progress_message,
            toolchain = toolchain,
        )
    else:
        _register_libtool_action(
            actions = actions,
            mnemonic = mnemonic,
            objects = objects,
            output = output,
            progress_message = progress_message,
            toolchain = toolchain,
        )

def _register_ar_action(
        actions,
        ar_executable,
        mnemonic,
        objects,
        output,
        progress_message,
        toolchain):
    """Registers an action that creates a static archive using `ar`.

    This function is used to create static archives when the Swift toolchain
    depends on a Linux toolchain.

    Args:
      actions: The object used to register actions.
      ar_executable: The path to the `ar` executable to use when creating the
          archive, if it should be used.
      mnemonic: The mnemonic to display when the action is executed.
      objects: A list of `File`s denoting object (.o) files that will be merged
          into the archive.
      output: A `File` to which the output archive will be written.
      progress_message: The progress message to display when the action is
          executed.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """

    args = actions.args()
    args.add("cr")
    args.add(output)
    args.add_all(objects)

    run_toolchain_action(
        actions = actions,
        arguments = [args],
        executable = ar_executable,
        inputs = objects,
        mnemonic = mnemonic,
        outputs = [output],
        progress_message = progress_message,
        toolchain = toolchain,
    )

def _register_libtool_action(
        actions,
        mnemonic,
        objects,
        output,
        progress_message,
        toolchain):
    """Registers an action that creates a static archive using `libtool`.

    This function is used to create static archives when the Swift toolchain
    depends on an Xcode toolchain.

    Args:
      actions: The object used to register actions.
      mnemonic: The mnemonic to display when the action is executed.
      objects: A list of `File`s denoting object (.o) files that will be merged
          into the archive.
      output: A `File` to which the output archive will be written.
      progress_message: The progress message to display when the action is
          executed.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    args = actions.args()
    args.add("-static")
    args.add("-o", output)

    # This must be the last argument in this set, because the filelist args object
    # immediately follows it in the invocation below.
    args.add("-filelist")

    filelist = actions.args()
    filelist.set_param_file_format("multiline")
    filelist.use_param_file("%s", use_always = True)
    filelist.add_all(objects)

    run_toolchain_action(
        actions = actions,
        arguments = [args, filelist],
        executable = "/usr/bin/libtool",
        inputs = objects,
        mnemonic = mnemonic,
        outputs = [output],
        progress_message = progress_message,
        toolchain = toolchain,
    )
