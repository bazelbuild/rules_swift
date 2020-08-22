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
load(
    ":feature_names.bzl",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD",
    "SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS",
)
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
load(":utils.bzl", "get_providers")

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

def _generate_module_map(
        actions,
        compilation_context,
        dependent_module_names,
        feature_configuration,
        module_name,
        target):
    """Generates the module map file for the given target.

    Args:
        actions: The object used to register actions.
        compilation_context: The C++ compilation context that provides the
            headers for the module.
        dependent_module_names: A `list` of names of Clang modules that are
            direct dependencies of the target whose module map is being written.
        feature_configuration: A Swift feature configuration.
        module_name: The name of the module.
        target: The target for which the module map is being generated.

    Returns: A `File` representing the generated module map.
    """

    # Determine if the toolchain requires module maps to use
    # workspace-relative paths or not, and other features controlling the
    # content permitted in the module map.
    workspace_relative = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
    )
    exclude_private_headers = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS,
    )

    if exclude_private_headers:
        private_headers = []
    else:
        private_headers = compilation_context.direct_private_headers

    module_map_file = derived_files.module_map(
        actions = actions,
        target_name = target.label.name,
    )
    write_module_map(
        actions = actions,
        dependent_module_names = dependent_module_names,
        module_map_file = module_map_file,
        module_name = module_name,
        private_headers = private_headers,
        public_headers = compilation_context.direct_public_headers,
        public_textual_headers = compilation_context.direct_textual_headers,
        workspace_relative = workspace_relative,
    )
    return module_map_file

def _module_info_for_target(
        target,
        aspect_ctx,
        compilation_context,
        dependent_module_names,
        feature_configuration):
    """Returns the module name and module map for the target.

    Args:
        aspect_ctx: The aspect context.
        target: The target for which the module map is being generated.
        compilation_context: The C++ compilation context that provides the
            headers for the module.
        dependent_module_names: A `list` of names of Clang modules that are
            direct dependencies of the target whose module map is being written.
        feature_configuration: A Swift feature configuration.

    Returns:
        A tuple containing the module name (a string) and module map file (a
        `File`) for the target. One or both of these values may be `None`.
    """
    attr = aspect_ctx.rule.attr

    if apple_common.Objc in target:
        # TODO(b/142867898): For `objc_library`, stop using the module map from
        # the Objc provider and generate our own. (For imported frameworks,
        # continue using the module map included with it.)
        objc = target[apple_common.Objc]
        module_maps = objc.direct_module_maps
        if not module_maps:
            return None, None

        # If the target isn't an `objc_library`, return its module map (so we
        # can propagate it) but don't return a module name; this will be used
        # later as an indicator that we shouldn't try to compile an explicit
        # module.
        if not aspect_ctx.rule.kind == "objc_library":
            return None, module_maps[0]

        module_name = getattr(attr, "module_name", None)
        if not module_name:
            module_name = derive_module_name(target.label)

        # For an `objc_library`, if we're emitting an explicit module, generate
        # our own module map instead of using the one generated by the native
        # Bazel `objc_library` implementation. This is necessary to get the
        # correct `use` decls for dependencies to include everything in
        # `SwiftInfo.direct_modules[].clang`, which will reference targets that
        # `ObjcProvider` doesn't know about, like SDK modules.
        # TODO(b/142867905): Once explicit modules are enabled by default, make
        # this the only code path (i.e., this aspect should generate all module
        # maps for `objc_library` targets).
        emit_c_module = is_feature_enabled(
            feature_configuration = feature_configuration,
            feature_name = SWIFT_FEATURE_EMIT_C_MODULE,
        )
        if not emit_c_module:
            return module_name, module_maps[0]

        module_map_file = _generate_module_map(
            actions = aspect_ctx.actions,
            compilation_context = compilation_context,
            dependent_module_names = dependent_module_names,
            feature_configuration = feature_configuration,
            module_name = module_name,
            target = target,
        )
        return module_name, module_map_file

    # For all other targets, there is no mechanism to provide a custom
    # module map, and we only generate one if the target is tagged.
    module_name = _tagged_target_module_name(
        label = target.label,
        tags = attr.tags,
    )
    if not module_name:
        return None, None

    module_map_file = _generate_module_map(
        actions = aspect_ctx.actions,
        compilation_context = compilation_context,
        dependent_module_names = dependent_module_names,
        feature_configuration = feature_configuration,
        module_name = module_name,
        target = target,
    )
    return module_name, module_map_file

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

    # TODO(b/142867898): Only check `CcInfo` once all rules correctly propagate
    # it.
    if CcInfo in target:
        compilation_context = target[CcInfo].compilation_context
    else:
        compilation_context = None

    if swift_infos:
        merged_swift_info = create_swift_info(swift_infos = swift_infos)
    else:
        merged_swift_info = None

    # Collect the names of Clang modules that the module being built directly
    # depends on.
    dependent_module_names = []
    for swift_info in swift_infos:
        for module in swift_info.direct_modules:
            if module.clang:
                dependent_module_names.append(module.name)

    module_name, module_map_file = _module_info_for_target(
        target = target,
        aspect_ctx = aspect_ctx,
        compilation_context = compilation_context,
        dependent_module_names = dependent_module_names,
        feature_configuration = feature_configuration,
    )

    if not module_map_file:
        if merged_swift_info:
            return [merged_swift_info]
        else:
            return []

    # TODO(b/159918106): We might get here without a module name if we had an
    # Objective-C rule other than `objc_library` that had a module map, such as
    # a framework import rule. For now, we won't support compiling those as
    # explicit modules; fix this.
    if module_name:
        # We only need to propagate the information from the compilation
        # contexts, but we can't merge those directly; we can only merge
        # `CcInfo` objects. So we "unwrap" the compilation context from each
        # provider and then "rewrap" it in a new provider that lacks the linking
        # context so that our merge operation does less work.
        target_and_deps_cc_infos = [
            CcInfo(compilation_context = compilation_context),
        ]
        for dep in getattr(attr, "deps", []):
            if CcInfo in dep:
                target_and_deps_cc_infos.append(
                    CcInfo(
                        compilation_context = dep[CcInfo].compilation_context,
                    ),
                )

        compilation_context_to_compile = cc_common.merge_cc_infos(
            direct_cc_infos = target_and_deps_cc_infos,
        ).compilation_context

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
    else:
        # TODO(b/159918106): Derive the module name *now* from the target label
        # so that we propagate it and preserve the old rule behavior, even
        # though this module name is probably wrong (for frameworks).
        module_name = derive_module_name(target.label)
        precompiled_module = None

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

    # TODO(b/142867898): Only check `CcInfo` once all native rules correctly
    # propagate both.
    if apple_common.Objc in target or CcInfo in target:
        return _handle_cc_target(
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
