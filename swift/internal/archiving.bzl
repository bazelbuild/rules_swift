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

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME")

def register_static_archive_action(
        actions,
        cc_feature_configuration,
        output,
        swift_toolchain,
        mnemonic = "Archive",
        objects = [],
        progress_message = None):
    """Registers an action that creates a static archive.

    Args:
        actions: The object used to register actions.
        cc_feature_configuration: The C++ feature configuration to use when constructing the
            action.
        output: A `File` to which the output archive will be written.
        swift_toolchain: The Swift toolchain provider to use when constructing the action.
        mnemonic: The mnemonic to display when the action is executed.
        objects: A list of `File`s denoting object (.o) files that will be merged into the archive.
        progress_message: The progress message to display when the action is executed.
    """
    archiver_path = cc_common.get_tool_for_action(
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        feature_configuration = cc_feature_configuration,
    )
    archiver_variables = cc_common.create_link_variables(
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        feature_configuration = cc_feature_configuration,
        is_using_linker = False,
        output_file = output.path,
    )

    command_line = cc_common.get_memory_inefficient_command_line(
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        feature_configuration = cc_feature_configuration,
        variables = archiver_variables,
    )
    args = actions.args()
    args.add_all(command_line)
    args.add_all(objects)

    env = cc_common.get_environment_variables(
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        feature_configuration = cc_feature_configuration,
        variables = archiver_variables,
    )

    actions.run(
        executable = archiver_path,
        arguments = [args],
        env = env,
        # TODO(allevato): It seems like the `cc_common` APIs should have a way to get this value
        # so that it can be handled consistently for the toolchain in use.
        execution_requirements = swift_toolchain.execution_requirements,
        inputs = depset(
            direct = objects,
            # TODO(bazelbuild/bazel#7427): Use `CcToolchainInfo` getters when they are available.
            transitive = [swift_toolchain.cc_toolchain_files],
        ),
        outputs = [output],
    )
