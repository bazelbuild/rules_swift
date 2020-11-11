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

"""Implementation of linking logic for Swift."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:partial.bzl", "partial")
load(
    "@bazel_tools//tools/build_defs/cc:action_names.bzl",
    "CPP_LINK_STATIC_LIBRARY_ACTION_NAME",
)
load(":derived_files.bzl", "derived_files")

def _register_static_library_link_action(
        actions,
        cc_feature_configuration,
        objects,
        output,
        swift_toolchain):
    """Registers an action that creates a static library.

    Args:
        actions: The object used to register actions.
        cc_feature_configuration: The C++ feature configuration to use when
            constructing the action.
        objects: A list of `File`s denoting object (`.o`) files that will be
            linked.
        output: A `File` to which the output library will be written.
        swift_toolchain: The Swift toolchain provider to use when constructing
            the action.
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

    filelist_args = actions.args()
    if swift_toolchain.linker_supports_filelist:
        args.add("-filelist")
        filelist_args.set_param_file_format("multiline")
        filelist_args.use_param_file("%s", use_always = True)
        filelist_args.add_all(objects)
    else:
        args.add_all(objects)

    env = cc_common.get_environment_variables(
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        feature_configuration = cc_feature_configuration,
        variables = archiver_variables,
    )

    execution_requirements_list = cc_common.get_execution_requirements(
        action_name = CPP_LINK_STATIC_LIBRARY_ACTION_NAME,
        feature_configuration = cc_feature_configuration,
    )
    execution_requirements = {req: "1" for req in execution_requirements_list}

    actions.run(
        arguments = [args, filelist_args],
        env = env,
        executable = archiver_path,
        execution_requirements = execution_requirements,
        inputs = depset(
            direct = objects,
            transitive = [swift_toolchain.cc_toolchain_info.all_files],
        ),
        mnemonic = "SwiftArchive",
        outputs = [output],
        progress_message = "Linking {}".format(output.short_path),
    )

def create_linker_input(
        *,
        actions,
        alwayslink,
        cc_feature_configuration,
        compilation_outputs,
        is_dynamic,
        is_static,
        library_name,
        objects,
        owner,
        swift_toolchain,
        additional_inputs = [],
        user_link_flags = []):
    """Creates a linker input for a library to link and additional inputs/flags.

    Args:
        actions: The object used to register actions.
        alwayslink: If True, create a static library that should be
            always-linked (having a `.lo` extension instead of `.a`). This
            argument is ignored if `is_static` is False.
        cc_feature_configuration: The C++ feature configuration to use when
            constructing the action.
        compilation_outputs: The compilation outputs from a Swift compile
            action, as returned by `swift_common.compile`, or None.
        is_dynamic: If True, declare and link a dynamic library.
        is_static: If True, declare and link a static library.
        library_name: The basename (without extension) of the libraries to
            declare.
        objects: A list of `File`s denoting object (`.o`) files that will be
            linked.
        owner: The `Label` of the target that owns this linker input.
        swift_toolchain: The Swift toolchain provider to use when constructing
            the action.
        additional_inputs: A list of extra `File` inputs passed to the linking
            action.
        user_link_flags: A list of extra flags to pass to the linking command.

    Returns:
        A tuple containing two elements:

        1.  A `LinkerInput` object containing the library that was created.
        2.  The single `LibraryToLink` object that is inside the linker input.
    """
    dynamic_library = None
    if is_dynamic:
        # TODO(b/70228246): Implement this.
        pass

    if is_static:
        static_library = derived_files.static_archive(
            actions = actions,
            alwayslink = alwayslink,
            link_name = library_name,
        )
        _register_static_library_link_action(
            actions = actions,
            cc_feature_configuration = cc_feature_configuration,
            objects = objects,
            output = static_library,
            swift_toolchain = swift_toolchain,
        )
    else:
        static_library = None

    library_to_link = cc_common.create_library_to_link(
        actions = actions,
        alwayslink = alwayslink,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        feature_configuration = cc_feature_configuration,
        pic_static_library = static_library,
        dynamic_library = dynamic_library,
    )
    linker_input = cc_common.create_linker_input(
        owner = owner,
        libraries = depset([library_to_link]),
        additional_inputs = depset(
            compilation_outputs.linker_inputs + additional_inputs,
        ),
        user_link_flags = depset(
            compilation_outputs.linker_flags + user_link_flags,
        ),
    )

    return linker_input, library_to_link

def register_link_binary_action(
        actions,
        additional_inputs,
        additional_linking_contexts,
        cc_feature_configuration,
        deps,
        grep_includes,
        name,
        objects,
        output_type,
        owner,
        stamp,
        swift_toolchain,
        user_link_flags):
    """Registers an action that invokes the linker to produce a binary.

    Args:
        actions: The object used to register actions.
        additional_inputs: A list of additional inputs to the link action,
            such as those used in `$(location ...)` substitution, linker
            scripts, and so forth.
        additional_linking_contexts: Additional linking contexts that provide
            libraries or flags that should be linked into the executable.
        cc_feature_configuration: The C++ feature configuration to use when
            constructing the action.
        deps: A list of targets representing additional libraries that will be
            passed to the linker.
        grep_includes: Used internally only.
        name: The name of the target being linked, which is used to derive the
            output artifact.
        objects: A list of object (.o) files that will be passed to the linker.
        output_type: A string indicating the output type; "executable" or
            "dynamic_library".
        owner: The `Label` of the target that owns this linker input.
        stamp: A tri-state value (-1, 0, or 1) that specifies whether link
            stamping is enabled. See `cc_common.link` for details about the
            behavior of this argument.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        user_link_flags: Additional flags passed to the linker. Any
            `$(location ...)` placeholders are assumed to have already been
            expanded.

    Returns:
        A `CcLinkingOutputs` object that contains the `executable` or
        `library_to_link` that was linked (depending on the value of the
        `output_type` argument).
    """
    linking_contexts = []

    for dep in deps:
        if CcInfo in dep:
            cc_info = dep[CcInfo]
            linking_contexts.append(cc_info.linking_context)

        # TODO(allevato): Remove all of this when `apple_common.Objc` goes away.
        if apple_common.Objc in dep:
            objc = dep[apple_common.Objc]

            static_framework_files = objc.static_framework_file.to_list()

            # We don't need to handle the `objc.sdk_framework` field here
            # because those values have also been put into the user link flags
            # of a CcInfo, but the others don't seem to have been.
            dep_link_flags = [
                "-l{}".format(dylib)
                for dylib in objc.sdk_dylib.to_list()
            ]
            dep_link_flags.extend([
                "-F{}".format(path)
                for path in objc.dynamic_framework_paths.to_list()
            ])
            dep_link_flags.extend(collections.before_each(
                "-framework",
                objc.dynamic_framework_names.to_list(),
            ))
            dep_link_flags.extend(static_framework_files)

            linking_contexts.append(
                cc_common.create_linking_context(
                    linker_inputs = depset([
                        cc_common.create_linker_input(
                            owner = owner,
                            user_link_flags = depset(dep_link_flags),
                        ),
                    ]),
                ),
            )

    linking_contexts.extend(additional_linking_contexts)

    _ignore = [grep_includes]  # Silence buildifier
    return cc_common.link(
        actions = actions,
        additional_inputs = additional_inputs,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        compilation_outputs = cc_common.create_compilation_outputs(
            objects = depset(objects),
            pic_objects = depset(objects),
        ),
        feature_configuration = cc_feature_configuration,
        name = name,
        user_link_flags = user_link_flags,
        linking_contexts = linking_contexts,
        link_deps_statically = True,
        output_type = output_type,
        stamp = stamp,
    )

def swift_runtime_linkopts(is_static, toolchain, is_test = False):
    """Returns the flags that should be passed when linking a Swift binary.

    This function provides the appropriate linker arguments to callers who need
    to link a binary using something other than `swift_binary` (for example, an
    application bundle containing a universal `apple_binary`).

    Args:
        is_static: A `Boolean` value indicating whether the binary should be
            linked against the static (rather than the dynamic) Swift runtime
            libraries.
        toolchain: The `SwiftToolchainInfo` provider of the toolchain whose
            linker options are desired.
        is_test: A `Boolean` value indicating whether the target being linked is
            a test target.

    Returns:
        A `list` of command line flags that should be passed when linking a
        binary against the Swift runtime libraries.
    """
    return partial.call(
        toolchain.linker_opts_producer,
        is_static = is_static,
        is_test = is_test,
    )
