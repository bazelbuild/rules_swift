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
load(
    ":utils.bzl",
    "compilation_context_for_explicit_module_compilation",
    "get_providers",
)

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

def _generate_module_map(
        actions,
        compilation_context,
        dependent_module_names,
        feature_configuration,
        module_name,
        target,
        umbrella_header):
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
        umbrella_header: A `File` representing an umbrella header that, if
            present, will be written into the module map instead of the list of
            headers in the compilation context.

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

    # Sort dependent module names and the headers to ensure a deterministic
    # order in the output file, in the event the compilation context would ever
    # change this on us. For files, use the execution path as the sorting key.
    def _path_sorting_key(file):
        return file.path

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
        umbrella_header = umbrella_header,
        workspace_relative = workspace_relative,
    )
    return module_map_file

def _objc_library_module_info(aspect_ctx):
    """Returns the `module_name` and `module_map` attrs for an `objc_library`.

    Args:
        aspect_ctx: The aspect context.

    Returns:
        A tuple containing the module name (a string) and the module map file (a
        `File`) specified as attributes on the `objc_library`. These values may
        be `None`.
    """
    attr = aspect_ctx.rule.attr

    # TODO(b/195019413): Deprecate the use of these attributes and use
    # `swift_interop_hint` to customize `objc_*` targets' module names and
    # module maps.
    module_name = getattr(attr, "module_name", None)
    module_map_file = None

    module_map_target = getattr(attr, "module_map", None)
    if module_map_target:
        module_map_files = module_map_target.files.to_list()
        if module_map_files:
            module_map_file = module_map_files[0]

    return module_name, module_map_file

# TODO(b/151667396): Remove j2objc-specific knowledge.
def _j2objc_umbrella_workaround(target):
    """Tries to find and return the umbrella header for a J2ObjC target.

    This is an unfortunate hack/workaround needed for J2ObjC, which needs to use
    an umbrella header that `#include`s, rather than `#import`s, the headers in
    the module due to the way they're segmented.

    It's also somewhat ugly in the way that it has to find the umbrella header,
    which is tied to Bazel's built-in module map generation. Since there's not a
    direct umbrella header field in `ObjcProvider`, we scan the target's actions
    to find the one that writes it out. Then, we return it and a new compilation
    context with the direct headers from the `ObjcProvider`, since the generated
    headers are not accessible via `CcInfo`--Java targets to which the J2ObjC
    aspect are applied do not propagate `CcInfo` directly, but a native Bazel
    provider that wraps the `CcInfo`, and we have no access to it from Starlark.

    Args:
        target: The target to which the aspect is being applied.

    Returns:
        A tuple containing two elements:

        *   A `File` representing the umbrella header generated by the target,
            or `None` if there was none.
        *   A `CcCompilationContext` containing the direct generated headers of
            the J2ObjC target (including the umbrella header), or `None` if the
            target did not generate an umbrella header.
    """
    for action in target.actions:
        if action.mnemonic != "UmbrellaHeader":
            continue

        umbrella_header = action.outputs.to_list()[0]
        compilation_context = cc_common.create_compilation_context(
            headers = depset(
                target[apple_common.Objc].direct_headers + [umbrella_header],
            ),
        )
        return umbrella_header, compilation_context

    return None, None

def _module_info_for_target(
        target,
        aspect_ctx,
        compilation_context,
        dependent_module_names,
        feature_configuration,
        module_name,
        umbrella_header):
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
        umbrella_header: A `File` representing an umbrella header that, if
            present, will be written into the module map instead of the list of
            headers in the compilation context.

    Returns:
        A tuple containing the module name (a string) and module map file (a
        `File`) for the target. One or both of these values may be `None`.
    """

    # Ignore `j2objc_library` targets. They exist to apply an aspect to their
    # dependencies, but the modules that should be imported are associated with
    # those dependencies. We'll produce errors if we try to read those headers
    # again from this target and create another module map with them.
    # TODO(b/151667396): Remove j2objc-specific knowledge.
    if aspect_ctx.rule.kind == "j2objc_library":
        return None, None

    # If a target doesn't have any headers, then don't generate a module map for
    # it. Such modules define nothing and only waste space on the compilation
    # command line and add more work for the compiler.
    if not compilation_context or (
        not compilation_context.direct_headers and
        not compilation_context.direct_textual_headers
    ):
        return None, None

    attr = aspect_ctx.rule.attr
    module_map_file = None

    # TODO: Remove once we cherry-pick the `swift_interop_hint` rule
    if not module_name and aspect_ctx.rule.kind == "cc_library":
        # For all other targets, there is no mechanism to provide a custom
        # module map, and we only generate one if the target is tagged.
        module_name = _tagged_target_module_name(
            label = target.label,
            tags = attr.tags,
        )
        if not module_name:
            return None, None

    if not module_name:
        if apple_common.Objc not in target:
            return None, None

        if aspect_ctx.rule.kind == "objc_library":
            module_name, module_map_file = _objc_library_module_info(aspect_ctx)

        # If it was an `objc_library` without an explicit module name, or it
        # was some other `Objc`-providing target, derive the module name
        # now.
        if not module_name:
            module_name = derive_module_name(target.label)

    # If we didn't get a module map above, generate it now.
    if not module_map_file:
        module_map_file = _generate_module_map(
            actions = aspect_ctx.actions,
            compilation_context = compilation_context,
            dependent_module_names = dependent_module_names,
            feature_configuration = feature_configuration,
            module_name = module_name,
            target = target,
            umbrella_header = umbrella_header,
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

    all_swift_infos = (
        swift_infos + swift_toolchain.clang_implicit_deps_providers.swift_infos
    )

    # Collect the names of Clang modules that the module being built directly
    # depends on.
    dependent_module_names = []
    for swift_info in all_swift_infos:
        for module in swift_info.direct_modules:
            if module.clang:
                dependent_module_names.append(module.name)

    # If we weren't passed a module map (i.e., from a `_SwiftInteropInfo`
    # provider), infer it and the module name based on properties of the rule to
    # support legacy rules.
    if not module_map_file:
        # TODO(b/151667396): Remove j2objc-specific knowledge.
        umbrella_header, new_compilation_context = _j2objc_umbrella_workaround(
            target = target,
        )
        if umbrella_header:
            compilation_context = new_compilation_context

        module_name, module_map_file = _module_info_for_target(
            target = target,
            aspect_ctx = aspect_ctx,
            compilation_context = compilation_context,
            dependent_module_names = dependent_module_names,
            feature_configuration = feature_configuration,
            module_name = module_name,
            umbrella_header = umbrella_header,
        )

    if not module_map_file:
        if all_swift_infos:
            return [create_swift_info(swift_infos = swift_infos)]
        else:
            return []

    compilation_context_to_compile = (
        compilation_context_for_explicit_module_compilation(
            compilation_contexts = [compilation_context],
            deps = getattr(attr, "deps", []),
        )
    )
    precompiled_module = precompile_clang_module(
        actions = aspect_ctx.actions,
        cc_compilation_context = compilation_context_to_compile,
        feature_configuration = feature_configuration,
        module_map_file = module_map_file,
        module_name = module_name,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = target.label.name,
    )

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

def _compilation_context_for_target(target):
    """Gets the compilation context to use when compiling this target's module.

    This function also handles the special case of a target that propagates an
    `apple_common.Objc` provider in addition to its `CcInfo` provider, where the
    former contains strict include paths that must also be added when compiling
    the module.

    Args:
        target: The target to which the aspect is being applied.

    Returns:
        A `CcCompilationContext` that contains the headers of the target being
        compiled.
    """
    if CcInfo not in target:
        return None

    compilation_context = target[CcInfo].compilation_context

    if apple_common.Objc in target:
        strict_includes = target[apple_common.Objc].strict_include
        if strict_includes:
            compilation_context = cc_common.merge_compilation_contexts(
                compilation_contexts = [
                    compilation_context,
                    cc_common.create_compilation_context(
                        includes = strict_includes,
                    ),
                ],
            )

    return compilation_context

def _swift_clang_module_aspect_impl(target, aspect_ctx):
    # Do nothing if the target already propagates `SwiftInfo`.
    if SwiftInfo in target:
        return []

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
            compilation_context = _compilation_context_for_target(target),
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
