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

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "@build_bazel_apple_support//lib:framework_migration.bzl",
    "framework_migration",
)
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "CPP_LINK_STATIC_LIBRARY_ACTION_NAME")
load(":actions.bzl", "run_swift_action")
load(":derived_files.bzl", "derived_files")
load(":utils.bzl", "collect_cc_libraries", "objc_provider_framework_name")

def _register_static_library_link_action(
        actions,
        cc_feature_configuration,
        objects,
        output,
        swift_toolchain):
    """Registers an action that creates a static library.

    Args:
        actions: The object used to register actions.
        cc_feature_configuration: The C++ feature configuration to use when constructing the
            action.
        objects: A list of `File`s denoting object (`.o`) files that will be linked.
        output: A `File` to which the output library will be written.
        swift_toolchain: The Swift toolchain provider to use when constructing the action.
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
            transitive = [swift_toolchain.cc_toolchain_info.all_files],
        ),
        mnemonic = "SwiftArchive",
        outputs = [output],
        progress_message = "Linking {}".format(output.short_path),
    )

def register_libraries_to_link(
        actions,
        alwayslink,
        cc_feature_configuration,
        is_dynamic,
        is_static,
        library_name,
        objects,
        swift_toolchain):
    """Declares files for the requested libraries and registers actions to link them.

    Args:
        actions: The object used to register actions.
        alwayslink: If True, create a static library that should be always-linked (having a `.lo`
            extension instead of `.a`). This argument is ignored if `is_static` is False.
        cc_feature_configuration: The C++ feature configuration to use when constructing the
            action.
        is_dynamic: If True, declare and link a dynamic library.
        is_static: If True, declare and link a static library.
        library_name: The basename (without extension) of the libraries to declare.
        objects: A list of `File`s denoting object (`.o`) files that will be linked.
        swift_toolchain: The Swift toolchain provider to use when constructing the action.

    Returns:
        A `LibraryToLink` object containing the libraries that were created.
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

    return cc_common.create_library_to_link(
        actions = actions,
        alwayslink = alwayslink,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        feature_configuration = cc_feature_configuration,
        pic_static_library = static_library,
        dynamic_library = dynamic_library,
    )

def register_link_executable_action(
        actions,
        action_environment,
        additional_linking_contexts,
        cc_feature_configuration,
        clang_executable,
        deps,
        expanded_linkopts,
        inputs,
        mnemonic,
        objects,
        outputs,
        progress_message,
        rule_specific_args,
        swift_toolchain):
    """Registers an action that invokes `clang` to link object files.

    Args:
        actions: The object used to register actions.
        action_environment: A `dict` of environment variables that should be set for the compile
            action.
        additional_linking_contexts: Additional linking contexts that provide libraries or flags
            that should be linked into the executable.
        cc_feature_configuration: The C++ feature configuration to use when constructing the
            action.
        clang_executable: The path to the `clang` executable that will be invoked to link, which is
            assumed to be present among the tools that the toolchain passes to its action
            registrars. If this is `None`, then simply `clang` will be used with the assumption that
            the registrar knows where and how to find it.
        deps: A list of `deps` representing additional libraries that will be passed to the linker.
        expanded_linkopts: A list of strings representing options passed to the linker. Any
            `$(location ...)` placeholders are assumed to have already been expanded.
        inputs: A `depset` containing additional inputs to the link action, such as those used in
            `$(location ...)` substitution, or libraries that need to be linked.
        mnemonic: The mnemonic printed by Bazel when the action executes.
        objects: A list of object (.o) files that will be passed to the linker.
        outputs: A list of `File`s that should be passed as the outputs of the link action.
        progress_message: The progress message printed by Bazel when the action executes.
        rule_specific_args: Additional arguments that are rule-specific that will be passed to
            `clang`.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    if not clang_executable:
        clang_executable = "clang"

    common_args = actions.args()

    # TODO(b/133833674): Remove this and get the executable from CROSSTOOL (see the comment at
    # the end of the function for more information).
    common_args.add(clang_executable)

    deps_libraries = []

    additional_input_depsets = []
    all_linkopts = list(expanded_linkopts)
    deps_dynamic_framework_names = []
    deps_dynamic_framework_paths = []
    deps_static_framework_files = []
    deps_sdk_dylibs = []
    deps_sdk_frameworks = []
    for dep in deps:
        if CcInfo in dep:
            cc_info = dep[CcInfo]
            additional_input_depsets.append(cc_info.linking_context.additional_inputs)
            all_linkopts.extend(cc_info.linking_context.user_link_flags)
            deps_libraries.extend(
                collect_cc_libraries(cc_info = cc_info, include_pic_static = True),
            )
        if apple_common.Objc in dep:
            objc = dep[apple_common.Objc]
            if framework_migration.is_post_framework_migration():
                deps_dynamic_framework_names.append(objc.dynamic_framework_names)
                deps_dynamic_framework_paths.append(objc.dynamic_framework_paths)
                deps_static_framework_files.append(objc.static_framework_file)
            else:
                deps_dynamic_framework_names.append(depset(
                    [
                        objc_provider_framework_name(fdir)
                        for fdir in objc.dynamic_framework_dir.to_list()
                    ],
                ))
                deps_dynamic_framework_paths.append(depset(
                    [fdir.dirname for fdir in objc.dynamic_framework_dir.to_list()],
                ))
                deps_static_framework_files.append(depset(
                    [
                        paths.join(fdir, objc_provider_framework_name(fdir))
                        for fdir in objc.framework_dir.to_list()
                    ],
                ))
            deps_sdk_dylibs.append(objc.sdk_dylib)
            deps_sdk_frameworks.append(objc.sdk_framework)

    for linking_context in additional_linking_contexts:
        additional_input_depsets.append(linking_context.additional_inputs)
        all_linkopts.extend(linking_context.user_link_flags)
        for library in linking_context.libraries_to_link:
            if library.pic_static_library:
                deps_libraries.append(library.pic_static_library)
            elif library.static_library:
                deps_libraries.append(library.static_library)

    libraries = depset(deps_libraries, order = "topological")
    link_input_depsets = [
        libraries,
        inputs,
    ] + additional_input_depsets

    link_input_args = actions.args()
    link_input_args.set_param_file_format("multiline")
    link_input_args.use_param_file("@%s", use_always = True)
    link_input_args.add_all(objects)

    is_darwin = swift_toolchain.system_name == "darwin"
    link_input_args.add_all(libraries, map_each = (
        _link_library_darwin_map_fn if is_darwin else _link_library_linux_map_fn
    ))

    # Add various requirements from propagated Objective-C frameworks:
    # * Static prebuilt framework binaries are passed as regular arguments.
    link_input_args.add_all(
        depset(transitive = deps_static_framework_files),
    )

    # * `sdk_dylibs` values are passed with `-l`.
    link_input_args.add_all(depset(transitive = deps_sdk_dylibs), format_each = "-l%s")

    # * `sdk_frameworks` values are passed with `-framework`.
    link_input_args.add_all(depset(transitive = deps_sdk_frameworks), before_each = "-framework")

    # * Dynamic prebuilt frameworks are passed by providing their parent directory as a search path
    #   using `-F` and the framework name as `-framework`.
    link_input_args.add_all(
        depset(transitive = deps_dynamic_framework_paths),
        format_each = "-F%s",
    )
    link_input_args.add_all(
        depset(transitive = deps_dynamic_framework_names),
        before_each = "-framework",
    )

    # If the C++ toolchain provides an embedded runtime, include it. See the documentation for
    # `CcToolchainInfo.{dynamic,static}_runtime_lib` for an explanation of the feature check:
    # https://docs.bazel.build/versions/master/skylark/lib/CcToolchainInfo.html#static_runtime_lib
    if cc_common.is_enabled(
        feature_configuration = cc_feature_configuration,
        feature_name = "static_link_cpp_runtimes",
    ):
        # TODO(b/70228246): Call dynamic_runtime_lib if dynamic linking.
        cc_runtime_libs = swift_toolchain.cc_toolchain_info.static_runtime_lib(
            feature_configuration = cc_feature_configuration,
        )
        link_input_args.add_all(cc_runtime_libs)
        link_input_depsets.append(cc_runtime_libs)

    user_args = actions.args()
    user_args.add_all(all_linkopts)

    execution_requirements = swift_toolchain.execution_requirements

    # TODO(b/133833674): Even though we're invoking clang, not swift, we do so through the
    # worker (in non-persistent mode) to get the necessary `xcrun` wrapping and placeholder
    # substitution on macOS. This shouldn't actually be necessary; we should be able to query
    # CROSSTOOL for the linker tool and that should include the correct wrapping. However, the
    # Bazel OSX CROSSTOOL currently uses `cc_wrapper.sh` instead of `wrapped_clang` for C++
    # linking actions (it properly uses `wrapped_clang` for Objective-C linking), so until that
    # is resolved (https://github.com/bazelbuild/bazel/pull/8495), we have to use this workaround.
    # This also means that, until we migrate to `wrapped_clang`, we're missing out on other
    # features like dSYM extraction, but that's actually not any different that the situation
    # today.
    run_swift_action(
        actions = actions,
        arguments = [
            common_args,
            link_input_args,
            rule_specific_args,
            user_args,
        ],
        env = action_environment,
        execution_requirements = execution_requirements,
        inputs = depset(
            objects,
            transitive = link_input_depsets + [
                swift_toolchain.cc_toolchain_info.all_files,
            ],
        ),
        mnemonic = mnemonic,
        outputs = outputs,
        progress_message = progress_message,
        swift_toolchain = swift_toolchain,
    )

def _link_library_darwin_map_fn(lib):
    """Maps a library to the appropriate flags to link them.

    This function handles `alwayslink` (.lo) libraries correctly by passing them with
    `-force_load`.

    Args:
        lib: A `File`, passed in when the calling `Args` object is ready to map it to an argument.

    Returns:
        A list of command-line arguments (strings) that link the library correctly.
    """
    if lib.basename.endswith(".lo"):
        return "-Wl,-force_load,{lib}".format(lib = lib.path)
    else:
        return lib.path

def _link_library_linux_map_fn(lib):
    """Maps a library to the appropriate flags to link them.

    This function handles `alwayslink` (.lo) libraries correctly by surrounding them with
    `--(no-)whole-archive`.

    Args:
        lib: A `File`, passed in when the calling `Args` object is ready to map it to an argument.

    Returns:
        A list of command-line arguments (strings) that link the library correctly.
    """
    if lib.basename.endswith(".lo"):
        return "-Wl,--whole-archive,{lib},--no-whole-archive".format(lib = lib.path)
    else:
        return lib.path
