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

load(":actions.bzl", "run_toolchain_action", "run_toolchain_shell_action")
load(":derived_files.bzl", "derived_files")

def register_static_archive_action(
        actions,
        ar_executable,
        output,
        toolchain,
        libraries = [],
        mnemonic = "Archive",
        objects = []):
    """Registers actions that create a static archive.

    Args:
      actions: The object used to register actions.
      ar_executable: The path to the `ar` executable to use when creating the
          archive, if it should be used.
      output: A `File` to which the output archive will be written.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
      libraries: A list of `File`s representing static libraries whose contents
          will be merged into the output archive.
      mnemonic: The mnemonic to display when the action is executed.
      objects: A list of `File`s denoting object (.o) files that will be merged
          into the archive.
    """
    if ar_executable:
        _register_ar_action(
            actions = actions,
            ar_executable = ar_executable,
            libraries = libraries,
            mnemonic = mnemonic,
            objects = objects,
            output = output,
            toolchain = toolchain,
        )
    else:
        _register_libtool_action(
            actions = actions,
            libraries = libraries,
            mnemonic = mnemonic,
            objects = objects,
            output = output,
            toolchain = toolchain,
        )

def _register_ar_action(
        actions,
        ar_executable,
        libraries,
        mnemonic,
        objects,
        output,
        toolchain):
    """Registers an action that creates a static archive using `ar`.

    This function is used to create static archives when the Swift toolchain
    depends on a Linux toolchain.

    Args:
      actions: The object used to register actions.
      ar_executable: The path to the `ar` executable to use when creating the
          archive, if it should be used.
      libraries: A list of `File`s representing static libraries whose contents
          will be merged into the output archive.
      mnemonic: The mnemonic to display when the action is executed.
      objects: A list of `File`s denoting object (.o) files that will be merged
          into the archive.
      output: A `File` to which the output archive will be written.
      toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    mri_commands = [
        "create /tmp/%s" % output.basename,
    ] + [
        "addmod %s" % object_file.path
        for object_file in objects
    ] + [
        "addlib %s" % library.path
        for library in libraries
    ] + [
        "save",
        "end",
    ]

    mri_script = derived_files.ar_mri_script(actions, for_archive = output)
    actions.write(
        content = "\n".join(mri_commands),
        output = mri_script,
    )

    command = " && ".join([
        'MRI_SCRIPT="$PWD/$1"',
        'ARCHIVE="$PWD/$2"',
        '%s -M < "$MRI_SCRIPT"' % ar_executable,
        'cp /tmp/%s "$ARCHIVE"' % output.basename,
    ])

    args = actions.args()
    args.add(mri_script)
    args.add(output)

    run_toolchain_shell_action(
        actions = actions,
        toolchain = toolchain,
        arguments = [args],
        command = command,
        inputs = [mri_script] + libraries + objects,
        mnemonic = mnemonic,
        outputs = [output],
    )

def _register_libtool_action(
        actions,
        libraries,
        mnemonic,
        objects,
        output,
        toolchain):
    """Registers an action that creates a static archive using `libtool`.

    This function is used to create static archives when the Swift toolchain
    depends on an Xcode toolchain.

    Args:
      actions: The object used to register actions.
      libraries: A list of `File`s representing static libraries whose contents
          will be merged into the output archive.
      mnemonic: The mnemonic to display when the action is executed.
      objects: A list of `File`s denoting object (.o) files that will be merged
          into the archive.
      output: A `File` to which the output archive will be written.
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
    filelist.add_all(libraries)

    run_toolchain_action(
        actions = actions,
        toolchain = toolchain,
        arguments = [args, filelist],
        executable = "/usr/bin/libtool",
        inputs = libraries + objects,
        mnemonic = mnemonic,
        outputs = [output],
    )
