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
load(":actions.bzl", "is_action_enabled", "swift_action_names")
load(":autolinking.bzl", "register_autolink_extract_action")
load(
    ":debugging.bzl",
    "ensure_swiftmodule_is_embedded",
    "should_embed_swiftmodule_for_debugging",
)
load(":derived_files.bzl", "derived_files")
load(":features.bzl", "get_cc_feature_configuration")

def create_linking_context_from_compilation_outputs(
        *,
        actions,
        additional_inputs = [],
        alwayslink = False,
        compilation_outputs,
        feature_configuration,
        label,
        linking_contexts = [],
        module_context,
        name = None,
        swift_toolchain,
        user_link_flags = []):
    """Creates a linking context from the outputs of a Swift compilation.

    On some platforms, this function will spawn additional post-compile actions
    for the module in order to add their outputs to the linking context. For
    example, if the toolchain that requires a "module-wrap" invocation to embed
    the `.swiftmodule` into an object file for debugging purposes, or if it
    extracts auto-linking information from the object files to generate a linker
    command line parameters file, those actions will be created here.

    Args:
        actions: The context's `actions` object.
        additional_inputs: A `list` of `File`s containing any additional files
            that are referenced by `user_link_flags` and therefore need to be
            propagated up to the linker.
        alwayslink: If True, any binary that depends on the providers returned
            by this function will link in all of the library's object files,
            even if some contain no symbols referenced by the binary.
        compilation_outputs: A `CcCompilationOutputs` value containing the
            object files to link. Typically, this is the second tuple element in
            the value returned by `swift_common.compile`.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        label: The `Label` of the target being built. This is used as the owner
            of the linker inputs created for post-compile actions (if any), and
            the label's name component also determines the name of the artifact
            unless it is overridden by the `name` argument.
        linking_contexts: A `list` of `CcLinkingContext`s containing libraries
            from dependencies.
        name: A string that is used to derive the name of the library or
            libraries linked by this function. If this is not provided or is a
            falsy value, the name component of the `label` argument is used.
        module_context: The module context returned by `swift_common.compile`
            containing information about the Swift module that was compiled.
            Typically, this is the first tuple element in the value returned by
            `swift_common.compile`.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        user_link_flags: A `list` of strings containing additional flags that
            will be passed to the linker for any binary that links with the
            returned linking context.

    Returns:
        A tuple of `(CcLinkingContext, CcLinkingOutputs)` containing the linking
        context to be propagated by the caller's `CcInfo` provider and the
        artifact representing the library that was linked, respectively.
    """
    extra_linking_contexts = [
        cc_info.linking_context
        for cc_info in swift_toolchain.implicit_deps_providers.cc_infos
    ]

    if module_context and module_context.swift:
        post_compile_linker_inputs = []

        # Ensure that the .swiftmodule file is embedded in the final library or
        # binary for debugging purposes.
        if should_embed_swiftmodule_for_debugging(
            feature_configuration = feature_configuration,
            module_context = module_context,
        ):
            post_compile_linker_inputs.append(
                ensure_swiftmodule_is_embedded(
                    actions = actions,
                    feature_configuration = feature_configuration,
                    label = label,
                    swiftmodule = module_context.swift.swiftmodule,
                    swift_toolchain = swift_toolchain,
                ),
            )

        # Invoke an autolink-extract action for toolchains that require it.
        if is_action_enabled(
            action_name = swift_action_names.AUTOLINK_EXTRACT,
            swift_toolchain = swift_toolchain,
        ):
            autolink_file = derived_files.autolink_flags(
                actions = actions,
                target_name = label.name,
            )
            register_autolink_extract_action(
                actions = actions,
                autolink_file = autolink_file,
                feature_configuration = feature_configuration,
                object_files = compilation_outputs.objects,
                swift_toolchain = swift_toolchain,
            )
            post_compile_linker_inputs.append(
                cc_common.create_linker_input(
                    owner = label,
                    user_link_flags = depset(
                        ["@{}".format(autolink_file.path)],
                    ),
                    additional_inputs = depset([autolink_file]),
                ),
            )

        extra_linking_contexts.append(
            cc_common.create_linking_context(
                linker_inputs = depset(post_compile_linker_inputs),
            ),
        )

    if not name:
        name = label.name

    return cc_common.create_linking_context_from_compilation_outputs(
        actions = actions,
        feature_configuration = get_cc_feature_configuration(
            feature_configuration,
        ),
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        compilation_outputs = compilation_outputs,
        name = name,
        user_link_flags = user_link_flags,
        linking_contexts = linking_contexts + extra_linking_contexts,
        alwayslink = alwayslink,
        additional_inputs = additional_inputs,
        disallow_static_libraries = False,
        disallow_dynamic_library = True,
        grep_includes = None,
    )

def register_link_binary_action(
        actions,
        additional_inputs,
        additional_linking_contexts,
        cc_feature_configuration,
        compilation_outputs,
        deps,
        grep_includes,  # buildifier: disable=unused-variable
        name,
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
        compilation_outputs: A `CcCompilationOutputs` object containing object
            files that will be passed to the linker.
        deps: A list of targets representing additional libraries that will be
            passed to the linker.
        grep_includes: Used internally only.
        name: The name of the target being linked, which is used to derive the
            output artifact.
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
            dep_link_flags.extend([
                "-F{}".format(path)
                for path in objc.static_framework_paths.to_list()
            ])
            dep_link_flags.extend(collections.before_each(
                "-framework",
                objc.static_framework_names.to_list(),
            ))

            linking_contexts.append(
                cc_common.create_linking_context(
                    linker_inputs = depset([
                        cc_common.create_linker_input(
                            owner = owner,
                            user_link_flags = dep_link_flags,
                            additional_inputs = objc.static_framework_file,
                        ),
                    ]),
                ),
            )

    linking_contexts.extend(additional_linking_contexts)

    return cc_common.link(
        actions = actions,
        additional_inputs = additional_inputs,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        compilation_outputs = compilation_outputs,
        feature_configuration = cc_feature_configuration,
        name = name,
        user_link_flags = user_link_flags,
        linking_contexts = linking_contexts,
        link_deps_statically = True,
        output_type = output_type,
        stamp = stamp,
    )
