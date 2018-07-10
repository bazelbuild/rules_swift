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

load(":actions.bzl", "run_toolchain_action")
load(":deps.bzl", "collect_link_libraries")
load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo")
load(":utils.bzl", "collect_transitive")

def register_link_action(
        actions,
        action_environment,
        clang_executable,
        deps,
        expanded_linkopts,
        features,
        inputs,
        mnemonic,
        objects,
        outputs,
        rule_specific_args,
        toolchain,
        configuration = None):
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
        features: The list of features that are set on the target being linked.
        inputs: A `depset` containing additional inputs to the link action, such as those used in
            `$(location ...)` substitution, or libraries that need to be linked.
        mnemonic: The mnemonic printed by Bazel when the action executes.
        objects: A list of object (.o) files that will be passed to the linker.
        outputs: A list of `File`s that should be passed as the outputs of the link action.
        rule_specific_args: Additional arguments that are rule-specific that will be passed to
            `clang`.
        toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        configuration: The default configuration from which certain compilation options are
            determined, such as whether coverage is enabled. This object should be one obtained from
            a rule's `ctx.configuraton` field. If omitted, no default-configuration-specific options
            will be used.
    """
    if not clang_executable:
        clang_executable = "clang"

    common_args = actions.args()
    if "llvm_lld" in features:
        common_args.add("-fuse-ld=lld")

    common_args.add_all(_coverage_linkopts(configuration))

    if toolchain.stamp:
        stamp_lib_depsets = [toolchain.stamp.cc.libs]
    else:
        stamp_lib_depsets = []

    deps_libraries = []
    for dep in deps:
      deps_libraries.extend(collect_link_libraries(dep))

    libraries = depset(transitive = deps_libraries + stamp_lib_depsets, order = "topological")
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
    link_input_args.add_all(libraries, map_each = _link_library_map_fn)

    # TODO(b/70228246): Also support fully-dynamic mode.
    if toolchain.cc_toolchain_info:
        link_input_args.add("-static-libgcc")
        link_input_args.add("-lrt")
        link_input_args.add("-ldl")

    all_linkopts = depset(
        direct = expanded_linkopts,
        transitive = [
            dep[SwiftInfo].transitive_linkopts
            for dep in deps
            if SwiftInfo in dep
        ] + [
            depset(direct = dep.cc.link_flags)
            for dep in deps
            if hasattr(dep, "cc")
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
    )

def _coverage_linkopts(configuration):
    """Returns `clang` linking flags for code converage if enabled.

    This function takes advantage of the fact that even if we don't use `clang` to do any C/C++
    compilation, we can pass the equivalent coverage options to it and the driver will still pass
    the required instrumentation libraries to the underlying linker for us.

    Args:
        configuration: The default configuration from which certain linking options are determined,
            such as whether coverage is enabled. This object should be one obtained from a rule's
            `ctx.configuraton` field. If omitted, no default-configuration-specific options will be
            used.

    Returns:
        A list of linking flags that enable code coverage if requested.
    """
    if configuration and configuration.coverage_enabled:
        return ["-fprofile-instr-generate", "-fcoverage-mapping"]
    return []

def _link_library_map_fn(lib):
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
