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
load(":actions.bzl", "run_toolchain_action")
load(":deps.bzl", "collect_link_libraries")
load(":providers.bzl", "SwiftInfo")
load(":utils.bzl", "collect_transitive", "objc_provider_framework_name")

def register_link_action(
        actions,
        action_environment,
        clang_executable,
        deps,
        expanded_linkopts,
        inputs,
        mnemonic,
        objects,
        outputs,
        progress_message,
        rule_specific_args,
        toolchain):
    """Registers an action that invokes `clang` to link object files.

    Args:
        actions: The object used to register actions.
        action_environment: A `dict` of environment variables that should be set for the compile
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
        toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    if not clang_executable:
        clang_executable = "clang"

    common_args = actions.args()

    deps_libraries = []

    if toolchain.stamp:
        stamp_libs_to_link = []
        for library in toolchain.stamp[CcInfo].linking_context.libraries_to_link:
            if library.pic_static_library:
                stamp_libs_to_link.append(library.pic_static_library)
            elif library.static_library:
                stamp_libs_to_link.append(library.static_library)

        if stamp_libs_to_link:
            deps_libraries.append(depset(direct = stamp_libs_to_link))

    deps_dynamic_framework_names = []
    deps_dynamic_framework_paths = []
    deps_static_framework_files = []
    deps_sdk_dylibs = []
    deps_sdk_frameworks = []
    for dep in deps:
        deps_libraries.extend(collect_link_libraries(dep))
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

    libraries = depset(transitive = deps_libraries, order = "topological")
    link_input_depsets = [
        libraries,
        inputs,
        collect_transitive(deps, SwiftInfo, "transitive_additional_inputs"),
    ]

    link_input_args = actions.args()
    link_input_args.set_param_file_format("multiline")
    link_input_args.use_param_file("@%s", use_always = True)

    if toolchain.root_dir:
        runtime_object_path = "{root}/lib/swift/{system}/{cpu}/swiftrt.o".format(
            cpu = toolchain.cpu,
            root = toolchain.root_dir,
            system = toolchain.system_name,
        )
        link_input_args.add(runtime_object_path)

    link_input_args.add_all(objects)

    is_darwin = toolchain.system_name == "darwin"
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

    all_linkopts = depset(
        direct = expanded_linkopts,
        transitive = [
            dep[SwiftInfo].transitive_linkopts
            for dep in deps
            if SwiftInfo in dep
        ] + [
            depset(direct = dep[CcInfo].linking_context.user_link_flags)
            for dep in deps
            if CcInfo in dep
        ],
    ).to_list()

    # Workaround that removes a linker option that breaks swift binaries.
    # TODO(b/77640204): Remove this workaround.
    enable_text_relocation_linkopt = "-Wl,-z,notext"
    if enable_text_relocation_linkopt in all_linkopts:
        all_linkopts.remove(enable_text_relocation_linkopt)

    user_args = actions.args()
    user_args.add_all(all_linkopts)

    run_toolchain_action(
        actions = actions,
        toolchain = toolchain,
        arguments = [
            common_args,
            link_input_args,
            rule_specific_args,
            user_args,
        ],
        executable = clang_executable,
        inputs = depset(direct = objects, transitive = link_input_depsets),
        mnemonic = mnemonic,
        outputs = outputs,
        progress_message = progress_message,
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
