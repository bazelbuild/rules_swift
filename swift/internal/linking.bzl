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

load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftOverlayInfo",
)
load(
    ":debugging.bzl",
    "ensure_swiftmodule_is_embedded",
    "should_embed_swiftmodule_for_debugging",
)
load(":features.bzl", "configure_features", "get_cc_feature_configuration")
load(":toolchain_utils.bzl", "SWIFT_TOOLCHAIN_TYPE")
load(":utils.bzl", "get_swift_implicit_deps")

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def configure_features_for_binary(
        *,
        ctx,
        requested_features = [],
        swift_toolchain,
        unsupported_features = []):
    """Creates and returns the feature configuration for binary linking.

    This helper automatically handles common features for all Swift
    binary-creating targets, like code coverage.

    Args:
        ctx: The rule context.
        requested_features: Features that are requested for the target.
        swift_toolchain: The Swift toolchain provider.
        unsupported_features: Features that are unsupported for the target.

    Returns:
        The `FeatureConfiguration` that was created.
    """
    requested_features = list(requested_features)
    unsupported_features = list(unsupported_features)

    # Require static linking for now.
    requested_features.append("static_linking_mode")

    # Enable LLVM coverage in CROSSTOOL if this is a coverage build. Note that
    # we explicitly enable LLVM format and disable GCC format because the former
    # is the only one that Swift supports.
    if ctx.configuration.coverage_enabled:
        requested_features.append("llvm_coverage_map_format")
        unsupported_features.append("gcc_coverage_map_format")

    return configure_features(
        ctx = ctx,
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = unsupported_features,
    )

def _create_embedded_debugging_linking_context(
        *,
        actions,
        feature_configuration,
        label,
        module_context,
        swift_toolchain,
        toolchain_type):
    """Creates a linking context that embeds a .swiftmodule for debugging.

    Args:
        actions: The context's `actions` object.
        feature_configuration: A feature configuration obtained from
            `swift_common.configure_features`.
        label: The `Label` of the target being built. This is used as the owner
            of the linker inputs created for post-compile actions (if any), and
            the label's name component also determines the name of the artifact
            unless it is overridden by the `name` argument.
        module_context: The module context returned by `swift_common.compile`
            containing information about the Swift module that was compiled.
            Typically, this is the first tuple element in the value returned by
            `swift_common.compile`.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        toolchain_type: The toolchain type of the `swift_toolchain` which is
            used for the proper selection of the execution platform inside
            `run_toolchain_action`.

    Returns:
        A valid `CcLinkingContext`, or `None` if no linking context was created.
    """
    if (
        module_context and
        module_context.swift and
        should_embed_swiftmodule_for_debugging(
            feature_configuration = feature_configuration,
            module_context = module_context,
        )
    ):
        post_compile_linker_inputs = [
            ensure_swiftmodule_is_embedded(
                actions = actions,
                feature_configuration = feature_configuration,
                label = label,
                swiftmodule = module_context.swift.swiftmodule,
                swift_toolchain = swift_toolchain,
                toolchain_type = toolchain_type,
            ),
        ]
        return cc_common.create_linking_context(
            linker_inputs = depset(post_compile_linker_inputs),
        )

    return None

def create_linking_context_from_compilation_outputs(
        *,
        actions,
        additional_inputs = [],
        alwayslink = True,
        compilation_outputs,
        feature_configuration,
        label,
        linking_contexts = [],
        module_context,
        name = None,
        swift_toolchain,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
        user_link_flags = []):
    """Creates a linking context from the outputs of a Swift compilation.

    On some platforms, this function will spawn additional post-compile actions
    for the module in order to add their outputs to the linking context. For
    example, if the toolchain that requires a "module-wrap" invocation to embed
    the `.swiftmodule` into an object file for debugging purposes, that action
    will be created here.

    Args:
        actions: The context's `actions` object.
        additional_inputs: A `list` of `File`s containing any additional files
            that are referenced by `user_link_flags` and therefore need to be
            propagated up to the linker.
        alwayslink: If `False`, any binary that depends on the providers
            returned by this function will link in all of the library's object
            files only if there are symbol references. See the discussion on
            `swift_library` `alwayslink` for why that behavior could result
            in undesired results.
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
        toolchain_type: The toolchain type of the `swift_toolchain` which is
            used for the proper selection of the execution platform inside
            `run_toolchain_action`.
        user_link_flags: A `list` of strings containing additional flags that
            will be passed to the linker for any binary that links with the
            returned linking context.

    Returns:
        A tuple of `(CcLinkingContext, CcLinkingOutputs)` containing the linking
        context to be propagated by the caller's `CcInfo` provider and the
        artifact representing the library that was linked, respectively.
    """
    _, implicit_cc_infos = get_swift_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = swift_toolchain,
    )
    extra_linking_contexts = [
        cc_info.linking_context
        for cc_info in implicit_cc_infos
    ]

    debugging_linking_context = _create_embedded_debugging_linking_context(
        actions = actions,
        feature_configuration = feature_configuration,
        label = label,
        module_context = module_context,
        swift_toolchain = swift_toolchain,
        toolchain_type = toolchain_type,
    )
    if debugging_linking_context:
        extra_linking_contexts.append(debugging_linking_context)

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
    )

def malloc_linking_context(ctx):
    """Returns the linking context to use for the malloc implementation.

    Args:
        ctx: The rule context.

    Returns:
        The `CcLinkingContext` that contains the library to link for the malloc
        implementation.
    """
    malloc = ctx.attr._custom_malloc or ctx.attr.malloc
    return malloc[CcInfo].linking_context

def register_link_binary_action(
        *,
        actions,
        additional_inputs = [],
        additional_linking_contexts = [],
        additional_outputs = [],
        compilation_outputs,
        deps,
        feature_configuration,
        label,
        module_contexts = [],
        name = None,
        output_type,
        stamp,
        swift_toolchain,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
        user_link_flags = [],
        variables_extension = {}):
    """Registers an action that invokes the linker to produce a binary.

    Args:
        actions: The object used to register actions.
        additional_inputs: A list of additional inputs to the link action,
            such as those used in `$(location ...)` substitution, linker
            scripts, and so forth.
        additional_linking_contexts: Additional linking contexts that provide
            libraries or flags that should be linked into the executable.
        additional_outputs: Additional files that are outputs of the linking
            action but which are not among the return value of `cc_common.link`.
        compilation_outputs: A `CcCompilationOutputs` object containing object
            files that will be passed to the linker.
        deps: A list of targets representing additional libraries that will be
            passed to the linker.
        feature_configuration: The Swift feature configuration.
        label: The label of the target being linked, whose name is used to
            derive the output artifact if the `name` argument is not provided.
        module_contexts: A list of module contexts resulting from the
            compilation of the sources in the binary target, which are embedded
            in the binary for debugging if this is a debug build. This list may
            be empty if the target had no sources of its own.
        name: If provided, the name of the output file to generate. If not
            provided, the name of `label` will be used.
        output_type: A string indicating the output type; "executable" or
            "dynamic_library".
        stamp: A tri-state value (-1, 0, or 1) that specifies whether link
            stamping is enabled. See `cc_common.link` for details about the
            behavior of this argument.
        swift_toolchain: The `SwiftToolchainInfo` provider of the toolchain.
        toolchain_type: The toolchain type of the `swift_toolchain` which is
            used for the proper selection of the execution platform inside
            `run_toolchain_action`.
        user_link_flags: Additional flags passed to the linker. Any
            `$(location ...)` placeholders are assumed to have already been
            expanded.
        variables_extension: A dictionary containing additional crosstool
            variables that should be set for the linking action.

    Returns:
        A `CcLinkingOutputs` object that contains the `executable` or
        `library_to_link` that was linked (depending on the value of the
        `output_type` argument).
    """
    linking_contexts = [
        dep[CcInfo].linking_context
        for dep in deps
        if CcInfo in dep
    ] + [
        dep[SwiftOverlayInfo].linking_context
        for dep in deps
        if SwiftOverlayInfo in dep
    ] + additional_linking_contexts

    for module_context in module_contexts:
        debugging_linking_context = _create_embedded_debugging_linking_context(
            actions = actions,
            feature_configuration = feature_configuration,
            label = label,
            module_context = module_context,
            swift_toolchain = swift_toolchain,
            toolchain_type = toolchain_type,
        )
        if debugging_linking_context:
            linking_contexts.append(debugging_linking_context)

    # Collect linking contexts from any of the toolchain's implicit
    # dependencies.
    _, implicit_cc_infos = get_swift_implicit_deps(
        feature_configuration = feature_configuration,
        swift_toolchain = swift_toolchain,
    )
    linking_contexts.extend([
        cc_info.linking_context
        for cc_info in implicit_cc_infos
    ])

    return cc_common.link(
        actions = actions,
        additional_inputs = additional_inputs,
        additional_outputs = additional_outputs,
        cc_toolchain = swift_toolchain.cc_toolchain_info,
        compilation_outputs = compilation_outputs,
        feature_configuration = get_cc_feature_configuration(
            feature_configuration,
        ),
        name = name if name else label.name,
        user_link_flags = user_link_flags,
        linking_contexts = linking_contexts,
        link_deps_statically = True,
        output_type = output_type,
        stamp = stamp,
        variables_extension = variables_extension,
    )
