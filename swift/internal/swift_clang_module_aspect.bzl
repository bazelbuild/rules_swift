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

"""Propagates unified `SwiftInfo` providers for C/Objective-C targets."""

load(":attrs.bzl", "swift_toolchain_attrs")
load(":compiling.bzl", "derive_module_name", "precompile_clang_module")
load(":derived_files.bzl", "derived_files")
load(":feature_names.bzl", "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD")
load(":features.bzl", "configure_features", "is_feature_enabled")
load(":module_maps.bzl", "write_module_map")
load(
    ":providers.bzl",
    "SwiftInfo",
    "SwiftToolchainInfo",
    "create_clang_module",
    "create_module",
    "create_swift_info",
)
load(":utils.bzl", "direct_preserving_compilation_context", "get_providers")

_MULTIPLE_TARGET_ASPECT_ATTRS = [
    "deps",
    # TODO(b/151667396): Remove j2objc-specific attributes when possible.
    "exports",
    "runtime_deps",
]

_SINGLE_TARGET_ASPECT_ATTRS = [
    # TODO(b/151667396): Remove j2objc-specific attributes when possible.
    "_jre_lib",
]

def _tagged_target_module_name(label, tags):
    """Returns the module name of a `swift_module`-tagged target.

    The `swift_module` tag may take one of two forms:

    *   `swift_module`: By itself, this indicates that the target is compatible
        with Swift and should be given a module name that is derived from its
        target label.
    *   `swift_module=name`: The module should be given the name `name`.

    If the `swift_module` tag is not present, no module name is used or
    computed.

    Since tags are unprocessed strings, nothing prevents the `swift_module` tag
    from being listed multiple times on the same target with different values.
    For this reason, the aspect uses the _last_ occurrence that it finds in the
    list.

    Args:
        label: The target label from which a module name should be derived, if
            necessary.
        tags: The list of tags from the `cc_library` target to which the aspect
            is being applied.

    Returns:
        If the `swift_module` tag was present, then the return value is the
        explicit name if it was of the form `swift_module=name`, or the
        label-derived name if the tag was not followed by a name. Otherwise, if
        the tag is not present, `None` is returned.
    """
    module_name = None
    for tag in tags:
        if tag == "swift_module":
            module_name = derive_module_name(label)
        elif tag.startswith("swift_module="):
            _, _, module_name = tag.partition("=")
    return module_name

def _handle_cc_target(
        aspect_ctx,
        feature_configuration,
        swift_infos,
        swift_toolchain,
        target):
    """Processes a C++ target that is a dependency of a Swift target.

    Args:
        aspect_ctx: The aspect's context.
        feature_configuration: The current feature configuration.
        swift_infos: The `SwiftInfo` providers of the current target's
            dependencies, which should be merged into the `SwiftInfo` provider
            created and returned for this C++ target.
        swift_toolchain: The Swift toolchain being used to build this target.
        target: The C++ target to which the aspect is currently being applied.

    Returns:
        A list of providers that should be returned by the aspect.
    """
    attr = aspect_ctx.rule.attr

    module_name = _tagged_target_module_name(
        label = target.label,
        tags = attr.tags,
    )

    if swift_infos:
        merged_swift_info = create_swift_info(swift_infos = swift_infos)
    else:
        merged_swift_info = None

    if not module_name:
        if merged_swift_info:
            return [merged_swift_info]
        else:
            return []

    # Determine if the toolchain requires module maps to use
    # workspace-relative paths or not.
    workspace_relative = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
    )

    module_map_file = derived_files.module_map(
        actions = aspect_ctx.actions,
        target_name = target.label.name,
    )
    write_module_map(
        actions = aspect_ctx.actions,
        headers = [
            file
            for target in attr.hdrs
            for file in target.files.to_list()
        ],
        module_map_file = module_map_file,
        module_name = module_name,
        textual_headers = [
            file
            for target in attr.textual_hdrs
            for file in target.files.to_list()
        ],
        workspace_relative = workspace_relative,
    )

    compilation_context = target[CcInfo].compilation_context

    compilation_contexts_to_compile = [compilation_context]
    compilation_contexts_to_compile.extend([
        dep[CcInfo].compilation_context
        for dep in attr.deps
        if CcInfo in dep
    ])
    compilation_context_to_compile = direct_preserving_compilation_context(
        compilation_contexts = compilation_contexts_to_compile,
    )

    precompiled_module = precompile_clang_module(
        actions = aspect_ctx.actions,
        bin_dir = aspect_ctx.bin_dir,
        cc_compilation_context = compilation_context_to_compile,
        feature_configuration = feature_configuration,
        genfiles_dir = aspect_ctx.genfiles_dir,
        module_map_file = module_map_file,
        module_name = module_name,
        swift_info = merged_swift_info,
        swift_toolchain = swift_toolchain,
        target_name = target.label.name,
    )

    return [create_swift_info(
        modules = [
            create_module(
                name = module_name,
                clang = create_clang_module(
                    compilation_context = compilation_context,
                    module_map = module_map_file,
                    precompiled_module = precompiled_module,
                ),
            ),
        ],
        swift_infos = swift_infos,
    )]

def _handle_objc_target(
        aspect_ctx,
        feature_configuration,
        swift_infos,
        swift_toolchain,
        target):
    """Processes an `Objc`-propagating dependency of a Swift target.

    This function moves Objective-C module map information into a value (as
    returned by `swift_common.create_clang_module`) in the `SwiftInfo` provider
    so that the compilation logic of the rules can treat `cc_library` and
    `objc_library` modules uniformly.

    Args:
        aspect_ctx: The aspect's context.
        feature_configuration: The current feature configuration.
        swift_infos: The `SwiftInfo` providers of the current target's
            dependencies, which should be merged into the `SwiftInfo` provider
            created and returned for this Objective-C target.
        swift_toolchain: The Swift toolchain being used to build this target.
        target: The Objective-C target to which the aspect is currently being
            applied.

    Returns:
        A list of providers that should be returned by the aspect.
    """
    attr = aspect_ctx.rule.attr

    # Some ObjC providers may not have module maps (e.g., providers that only
    # propagate legacy resource attributes or which otherwise do not provide
    # compilation context information).
    direct_module_maps = target[apple_common.Objc].direct_module_maps
    if not direct_module_maps:
        if swift_infos:
            return [create_swift_info(swift_infos = swift_infos)]
        else:
            return []

    module_map_file = direct_module_maps[0]

    # Use the `module_name` attribute if it exists for rules that let the user
    # explicitly specify it (e.g., `objc_library`). If the attribute does not
    # exist or has not been set, derive the module name.
    module_name = getattr(attr, "module_name", None)
    if not module_name:
        module_name = derive_module_name(target.label)

    # TODO(b/144372256): Protect against the case where some custom Objective-C
    # rules may not have a `CcInfo` provider by returning a dummy compilation
    # context until those rules are forced to migrate to the C++ APIs when the
    # relevant fields are removed from the Objc provider.
    if CcInfo in target:
        compilation_context = target[CcInfo].compilation_context
    else:
        compilation_context = cc_common.create_compilation_context()

    return [create_swift_info(
        modules = [
            create_module(
                name = module_name,
                clang = create_clang_module(
                    compilation_context = compilation_context,
                    module_map = module_map_file,
                    # TODO(b/142867898): Precompile the module and place it
                    # here.
                    precompiled_module = None,
                ),
            ),
        ],
        module_name = module_name,
        swift_infos = swift_infos,
    )]

def _swift_clang_module_aspect_impl(target, aspect_ctx):
    # Do nothing if the target already propagates `SwiftInfo`.
    if SwiftInfo in target:
        return []

    # Collect `SwiftInfo` providers from dependencies, based on the attributes
    # that this aspect traverses.
    attr = aspect_ctx.rule.attr
    deps = []
    for attr_name in _MULTIPLE_TARGET_ASPECT_ATTRS:
        deps.extend(getattr(attr, attr_name, []))
    for attr_name in _SINGLE_TARGET_ASPECT_ATTRS:
        dep = getattr(attr, attr_name, None)
        if dep:
            deps.append(dep)
    swift_infos = get_providers(deps, SwiftInfo)

    swift_toolchain = aspect_ctx.attr._toolchain_for_aspect[SwiftToolchainInfo]
    feature_configuration = configure_features(
        ctx = aspect_ctx,
        requested_features = aspect_ctx.features,
        swift_toolchain = swift_toolchain,
        unsupported_features = aspect_ctx.disabled_features,
    )

    # TODO(b/143292468): Stop checking the rule kind and look for the presence
    # of `CcInfo` once `CcInfo.compilation_context` propagates direct headers
    # and direct textual headers separately.
    if aspect_ctx.rule.kind == "cc_library":
        return _handle_cc_target(
            aspect_ctx = aspect_ctx,
            feature_configuration = feature_configuration,
            swift_infos = swift_infos,
            swift_toolchain = swift_toolchain,
            target = target,
        )
    elif apple_common.Objc in target:
        return _handle_objc_target(
            aspect_ctx = aspect_ctx,
            feature_configuration = feature_configuration,
            swift_infos = swift_infos,
            swift_toolchain = swift_toolchain,
            target = target,
        )

    # If it's any other rule, just merge the `SwiftInfo` providers from its
    # deps.
    if swift_infos:
        return [create_swift_info(swift_infos = swift_infos)]

    return []

swift_clang_module_aspect = aspect(
    attr_aspects = _MULTIPLE_TARGET_ASPECT_ATTRS + _SINGLE_TARGET_ASPECT_ATTRS,
    attrs = swift_toolchain_attrs(
        toolchain_attr_name = "_toolchain_for_aspect",
    ),
    doc = """\
Propagates unified `SwiftInfo` providers for targets that represent
C/Objective-C modules.

This aspect unifies the propagation of Clang module artifacts so that Swift
targets that depend on C/Objective-C targets can find the necessary module
artifacts, and so that Swift module artifacts are not lost when passing through
a non-Swift target in the build graph (for example, a `swift_library` that
depends on an `objc_library` that depends on a `swift_library`).

It also manages module map generation for `cc_library` targets that have the
`swift_module` tag. This tag may take one of two forms:

    *   `swift_module`: By itself, this indicates that the target is compatible
        with Swift and should be given a module name that is derived from its
        target label.
    *   `swift_module=name`: The module should be given the name `name`.

Note that the public headers of such `cc_library` targets must be parsable as C,
since Swift does not support C++ interop at this time.

Most users will not need to interact directly with this aspect, since it is
automatically applied to the `deps` attribute of all `swift_binary`,
`swift_library`, and `swift_test` targets. However, some rules may need to
provide custom propagation logic of C/Objective-C module dependencies; for
example, a rule that has a support library as a private attribute would need to
ensure that `SwiftInfo` providers for that library and its dependencies are
propagated to any targets that depend on it, since they would not be propagated
via `deps`. In this case, the custom rule can attach this aspect to that support
library's attribute and then merge its `SwiftInfo` provider with any others that
it propagates for its targets.
""",
    fragments = ["cpp"],
    implementation = _swift_clang_module_aspect_impl,
    required_aspect_providers = [
        [apple_common.Objc],
        [CcInfo],
    ],
)
