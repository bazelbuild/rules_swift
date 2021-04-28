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

_SwiftInteropInfo = provider(
    doc = """\
Contains minimal information required to allow `swift_clang_module_aspect` to
manage the creation of a `SwiftInfo` provider for a C/Objective-C target.
""",
    fields = {
        "module_map": """\
A `File` representing an existing module map that should be used to represent
the module, or `None` if the module map should be generated based on the headers
in the target's compilation context.
""",
        "module_name": """\
A string denoting the name of the module, or `None` if the name should be
derived automatically from the target label.
""",
        "requested_features": """\
A list of features that should be enabled for the target, in addition to those
supplied in the `features` attribute, unless the feature is otherwise marked as
unsupported (either on the target or by the toolchain). This allows the rule
implementation to supply an additional set of fixed features that should always
be enabled when the aspect processes that target; for example, a rule can
request that `swift.emit_c_module` always be enabled for its targets even if it
is not explicitly enabled in the toolchain or on the target directly.
""",
        "swift_infos": """\
A list of `SwiftInfo` providers from dependencies of the target, which will be
merged with the new `SwiftInfo` created by the aspect.
""",
        "unsupported_features": """\
A list of features that should be disabled for the target, in addition to those
supplied as negations in the `features` attribute. This allows the rule
implementation to supply an additional set of fixed features that should always
be disabled when the aspect processes that target; for example, a rule that
processes frameworks with headers that do not follow strict layering can request
that `swift.strict_module` always be disabled for its targets even if it is
enabled by default in the toolchain.
""",
    },
)

def create_swift_interop_info(
        *,
        module_map = None,
        module_name = None,
        requested_features = [],
        swift_infos = [],
        unsupported_features = []):
    """Returns a provider that lets a target expose C/Objective-C APIs to Swift.

    The provider returned by this function allows custom build rules written in
    Starlark to be uninvolved with much of the low-level machinery involved in
    making a Swift-compatible module. Such a target should propagate a `CcInfo`
    provider whose compilation context contains the headers that it wants to
    make into a module, and then also propagate the provider returned from this
    function.

    The simplest usage is for a custom rule to call
    `swift_common.create_swift_interop_info` passing it only the list of
    `SwiftInfo` providers from its dependencies; this tells
    `swift_clang_module_aspect` to derive the module name from the target label
    and create a module map using the headers from the compilation context.

    If the custom rule has reason to provide its own module name or module map,
    then it can do so using the `module_name` and `module_map` arguments.

    When a rule returns this provider, it must provide the full set of
    `SwiftInfo` providers from dependencies that will be merged with the one
    that `swift_clang_module_aspect` creates for the target itself; the aspect
    will not do so automatically. This allows the rule to not only add extra
    dependencies (such as support libraries from implicit attributes) but also
    exclude dependencies if necessary.

    Args:
        module_map: A `File` representing an existing module map that should be
            used to represent the module, or `None` (the default) if the module
            map should be generated based on the headers in the target's
            compilation context. If this argument is provided, then
            `module_name` must also be provided.
        module_name: A string denoting the name of the module, or `None` (the
            default) if the name should be derived automatically from the target
            label.
        requested_features: A list of features (empty by default) that should be
            requested for the target, which are added to those supplied in the
            `features` attribute of the target. These features will be enabled
            unless they are otherwise marked as unsupported (either on the
            target or by the toolchain). This allows the rule implementation to
            have additional control over features that should be supported by
            default for all instances of that rule as if it were creating the
            feature configuration itself; for example, a rule can request that
            `swift.emit_c_module` always be enabled for its targets even if it
            is not explicitly enabled in the toolchain or on the target
            directly.
        swift_infos: A list of `SwiftInfo` providers from dependencies, which
            will be merged with the new `SwiftInfo` created by the aspect.
        unsupported_features: A list of features (empty by default) that should
            be considered unsupported for the target, which are added to those
            supplied as negations in the `features` attribute. This allows the
            rule implementation to have additional control over features that
            should be disabled by default for all instances of that rule as if
            it were creating the feature configuration itself; for example, a
            rule that processes frameworks with headers that do not follow
            strict layering can request that `swift.strict_module` always be
            disabled for its targets even if it is enabled by default in the
            toolchain.

    Returns:
        A provider whose type/layout is an implementation detail and should not
        be relied upon.
    """
    if module_map and not module_name:
        fail("'module_name' must be specified when 'module_map' is specified.")

    return _SwiftInteropInfo(
        module_map = module_map,
        module_name = module_name,
        requested_features = requested_features,
        swift_infos = swift_infos,
        unsupported_features = unsupported_features,
    )

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

# TODO: Once bazel supports nested functions unify this with upstream
# Sort dependent module names and the headers to ensure a deterministic
# order in the output file, in the event the compilation context would ever
# change this on us. For files, use the execution path as the sorting key.
def _path_sorting_key(file):
    return file.path

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
        dependent_module_names = sorted(dependent_module_names),
        exported_module_ids = ["*"],
        module_map_file = module_map_file,
        module_name = module_name,
        private_headers = sorted(private_headers, key = _path_sorting_key),
        public_headers = sorted(
            compilation_context.direct_public_headers,
            key = _path_sorting_key,
        ),
        public_textual_headers = sorted(
            compilation_context.direct_textual_headers,
            key = _path_sorting_key,
        ),
        workspace_relative = workspace_relative,
    )
    return module_map_file

def _module_info_for_target(
        target,
        aspect_ctx,
        compilation_context,
        dependent_module_names,
        feature_configuration,
        module_name):
    """Returns the module name and module map for the target.

    Args:
        target: The target for which the module map is being generated.
        aspect_ctx: The aspect context.
        compilation_context: The C++ compilation context that provides the
            headers for the module.
        dependent_module_names: A `list` of names of Clang modules that are
            direct dependencies of the target whose module map is being written.
        feature_configuration: A Swift feature configuration.
        module_name: The module name to prefer (if we're generating a module map
            from `_SwiftInteropInfo`), or None to derive it from other
            properties of the target.

    Returns:
        A tuple containing the module name (a string) and module map file (a
        `File`) for the target. One or both of these values may be `None`.
    """
    attr = aspect_ctx.rule.attr

    if not module_name and apple_common.Objc in target:
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

        # If an `objc_library` doesn't have any headers (and doesn't specify an
        # explicit module map), then don't generate or propagate a module map
        # for it. Such modules define nothing and only waste space on the
        # compilation command line and add more work for the compiler.
        if not getattr(attr, "module_map", None) and not (
            compilation_context.direct_headers or
            compilation_context.direct_textual_headers
        ):
            return None, None

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

    # If a target doesn't have any headers (and if we're on this code path, it
    # didn't provide an explicit module map), then don't generate a module map
    # for it. Such modules define nothing and only waste space on the
    # compilation command line and add more work for the compiler.
    if not (
        compilation_context.direct_headers or
        compilation_context.direct_textual_headers
    ):
        return None, None

    if not module_name:
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

def _handle_module(
        aspect_ctx,
        compilation_context,
        feature_configuration,
        module_map_file,
        module_name,
        swift_infos,
        swift_toolchain,
        target):
    """Processes a C/Objective-C target that is a dependency of a Swift target.

    Args:
        aspect_ctx: The aspect's context.
        compilation_context: The `CcCompilationContext` containing the target's
            headers.
        feature_configuration: The current feature configuration.
        module_map_file: The `.modulemap` file that defines the module, or None
            if it should be inferred from other properties of the target (for
            legacy support).
        module_name: The name of the module, or None if it should be inferred
            from other properties of the target (for legacy support).
        swift_infos: The `SwiftInfo` providers of the current target's
            dependencies, which should be merged into the `SwiftInfo` provider
            created and returned for this target.
        swift_toolchain: The Swift toolchain being used to build this target.
        target: The C++ target to which the aspect is currently being applied.

    Returns:
        A list of providers that should be returned by the aspect.
    """
    attr = aspect_ctx.rule.attr

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

    # If we weren't passed a module map (i.e., from a `_SwiftInteropInfo`
    # provider), infer it and the module name based on properties of the rule to
    # support legacy rules.
    if not module_map_file:
        module_name, module_map_file = _module_info_for_target(
            target = target,
            aspect_ctx = aspect_ctx,
            compilation_context = compilation_context,
            dependent_module_names = dependent_module_names,
            feature_configuration = feature_configuration,
            module_name = module_name,
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
            if apple_common.Objc in dep:
                target_and_deps_cc_infos.append(
                    CcInfo(
                        compilation_context = cc_common.create_compilation_context(
                            includes = dep[apple_common.Objc].strict_include,
                        ),
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

    providers = [
        create_swift_info(
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
        ),
    ]

    if precompiled_module:
        providers.append(
            OutputGroupInfo(
                swift_explicit_module = depset([precompiled_module]),
            ),
        )

    return providers

def _swift_clang_module_aspect_impl(target, aspect_ctx):
    # Do nothing if the target already propagates `SwiftInfo`.
    if SwiftInfo in target:
        return []

    if CcInfo in target:
        compilation_context = target[CcInfo].compilation_context
    else:
        compilation_context = None

    requested_features = aspect_ctx.features
    unsupported_features = aspect_ctx.disabled_features

    if _SwiftInteropInfo in target:
        interop_info = target[_SwiftInteropInfo]
        module_map_file = interop_info.module_map
        module_name = (
            interop_info.module_name or derive_module_name(target.label)
        )
        swift_infos = interop_info.swift_infos
        requested_features.extend(interop_info.requested_features)
        unsupported_features.extend(interop_info.unsupported_features)
    else:
        module_map_file = None
        module_name = None

        # Collect `SwiftInfo` providers from dependencies, based on the
        # attributes that this aspect traverses.
        deps = []
        attr = aspect_ctx.rule.attr
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
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = unsupported_features,
    )

    if (
        _SwiftInteropInfo in target or
        apple_common.Objc in target or
        CcInfo in target
    ):
        return _handle_module(
            aspect_ctx = aspect_ctx,
            compilation_context = compilation_context,
            feature_configuration = feature_configuration,
            module_map_file = module_map_file,
            module_name = module_name,
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
