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
load(":features.bzl", "get_cc_feature_configuration", "is_feature_enabled")
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_LLD_GC_WORKAROUND",
    "SWIFT_FEATURE_OBJC_LINK_FLAGS",
    "SWIFT_FEATURE__FORCE_ALWAYSLINK_TRUE",
)
load(
    ":developer_dirs.bzl",
    "developer_dirs_linkopts",
)
load(":utils.bzl", "get_providers")

def create_linking_context_from_compilation_outputs(
        *,
        actions,
        additional_inputs = [],
        alwayslink = False,
        compilation_outputs,
        feature_configuration,
        is_test,
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
        is_test: Represents if the `testonly` value of the context.
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

    if not alwayslink:
        alwayslink = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE__FORCE_ALWAYSLINK_TRUE,
        )

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_LLD_GC_WORKAROUND,
    ):
        extra_linking_contexts.append(
            cc_common.create_linking_context(
                linker_inputs = depset([
                    cc_common.create_linker_input(
                        owner = label,
                        user_link_flags = depset(["-Wl,-z,nostart-stop-gc"]),
                    ),
                ]),
            ),
        )

    if is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OBJC_LINK_FLAGS,
    ):
        # TODO: Remove once we can rely on folks using the new toolchain
        extra_linking_contexts.append(
            cc_common.create_linking_context(
                linker_inputs = depset([
                    cc_common.create_linker_input(
                        owner = label,
                        user_link_flags = depset(["-ObjC"]),
                    ),
                ]),
            ),
        )

    if not name:
        name = label.name

    if is_test:
        developer_paths_linkopts = developer_dirs_linkopts(swift_toolchain.developer_dirs)
    else:
        developer_paths_linkopts = []

    return cc_common.create_linking_context_from_compilation_outputs(
        actions = actions,
        feature_configuration = get_cc_feature_configuration(
            feature_configuration,
        ),
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        compilation_outputs = compilation_outputs,
        name = name,
        user_link_flags = user_link_flags + developer_paths_linkopts,
        linking_contexts = linking_contexts + extra_linking_contexts,
        alwayslink = alwayslink,
        additional_inputs = additional_inputs,
        disallow_static_libraries = False,
        disallow_dynamic_library = True,
        grep_includes = None,
    )

def new_objc_provider(
        *,
        additional_link_inputs = [],
        additional_objc_infos = [],
        alwayslink = False,
        deps,
        feature_configuration,
        is_test,
        libraries_to_link,
        module_context,
        user_link_flags = [],
        swift_toolchain):
    """Creates an `apple_common.Objc` provider for a Swift target.

    Args:
        additional_link_inputs: Additional linker input files that should be
            propagated to dependents.
        additional_objc_infos: Additional `apple_common.Objc` providers from
            transitive dependencies not provided by the `deps` argument.
        alwayslink: If True, any binary that depends on the providers returned
            by this function will link in all of the library's object files,
            even if some contain no symbols referenced by the binary.
        deps: The dependencies of the target being built, whose `Objc` providers
            will be passed to the new one in order to propagate the correct
            transitive fields.
        feature_configuration: The Swift feature configuration.
        is_test: Represents if the `testonly` value of the context.
        libraries_to_link: A list (typically of one element) of the
            `LibraryToLink` objects from which the static archives (`.a` files)
            containing the target's compiled code will be retrieved.
        module_context: The module context as returned by
            `swift_common.compile`.
        user_link_flags: Linker options that should be propagated to dependents.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.

    Returns:
        An `apple_common.Objc` provider that should be returned by the calling
        rule.
    """

    # The link action registered by `apple_common.link_multi_arch_binary` only
    # looks at `Objc` providers, not `CcInfo`, for libraries to link.
    # Dependencies from an `objc_library` to a `cc_library` are handled as a
    # special case, but other `cc_library` dependencies (such as `swift_library`
    # to `cc_library`) would be lost since they do not receive the same
    # treatment. Until those special cases are resolved via the unification of
    # the Obj-C and C++ rules, we need to collect libraries from `CcInfo` and
    # put them into the new `Objc` provider.
    transitive_cc_libs = []
    for cc_info in get_providers(deps, CcInfo):
        static_libs = []
        for linker_input in cc_info.linking_context.linker_inputs.to_list():
            for library_to_link in linker_input.libraries:
                library = library_to_link.static_library
                if library:
                    static_libs.append(library)
        transitive_cc_libs.append(depset(static_libs, order = "topological"))

    direct_libraries = []
    force_load_libraries = []

    for library_to_link in libraries_to_link:
        library = library_to_link.static_library
        if library:
            direct_libraries.append(library)
            if alwayslink:
                force_load_libraries.append(library)

    extra_linkopts = []
    if feature_configuration and should_embed_swiftmodule_for_debugging(
        feature_configuration = feature_configuration,
        module_context = module_context,
    ):
        module_file = module_context.swift.swiftmodule
        extra_linkopts.append("-Wl,-add_ast_path,{}".format(module_file.path))
        debug_link_inputs = [module_file]
    else:
        debug_link_inputs = []

    if is_test:
        extra_linkopts.extend(developer_dirs_linkopts(swift_toolchain.developer_dirs))

    if feature_configuration and is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_OBJC_LINK_FLAGS,
    ):
        extra_linkopts.append("-ObjC")

    return apple_common.new_objc_provider(
        force_load_library = depset(
            force_load_libraries,
            order = "topological",
        ),
        library = depset(
            direct_libraries,
            transitive = transitive_cc_libs,
            order = "topological",
        ),
        link_inputs = depset(additional_link_inputs + debug_link_inputs),
        linkopt = depset(user_link_flags + extra_linkopts),
        providers = get_providers(
            deps,
            apple_common.Objc,
        ) + additional_objc_infos,
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

            is_bazel_6 = hasattr(apple_common, "link_multi_arch_static_library")
            if is_bazel_6:
                additional_inputs = objc.static_framework_file
            else:
                additional_inputs = depset(
                    transitive = [
                        objc.static_framework_file,
                        objc.imported_library,
                    ],
                )
                dep_link_flags.extend([
                    lib.path
                    for lib in objc.imported_library.to_list()
                ])

            linking_contexts.append(
                cc_common.create_linking_context(
                    linker_inputs = depset([
                        cc_common.create_linker_input(
                            owner = owner,
                            user_link_flags = dep_link_flags,
                            additional_inputs = additional_inputs,
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
