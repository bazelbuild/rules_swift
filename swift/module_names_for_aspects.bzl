# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""APIs that let aspects determine the Swift module names of targets.

These are kept separate from `module_name.bzl` so that the lightweight module
name derivation utilities in that file do not need to load the Swift providers.
"""

load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    "SwiftOverlayCompileInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:swift_interop_info.bzl",
    "SwiftInteropInfo",
)
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(":module_name.bzl", "derive_swift_module_name")
load(":providers.bzl", "SwiftInfo")
load(":swift_interop_info.bzl", "create_swift_interop_info")

visibility("public")

def find_swift_interop_info(*, aspect_ctx, target):
    """Finds a `SwiftInteropInfo` provider associated with the target.

    This function first looks at the target itself to determine if it propagated
    a `SwiftInteropInfo` provider directly (that is, its rule implementation
    function called `create_swift_interop_info`). If it did not, then the
    target's `aspect_hints` attribute is checked for a reference to a target
    that propagates `SwiftInteropInfo` (such as `swift_interop_hint`).

    It is an error if `aspect_hints` contains two or more targets that propagate
    `SwiftInteropInfo`, or if the target directly propagates the provider and
    there is also any target in `aspect_hints` that propagates it.

    Args:
        aspect_ctx: The aspect's context.
        target: The target to which the aspect is currently being applied.

    Returns:
        The `SwiftInteropInfo` associated with the target, if found; otherwise,
        `None`.
    """
    if SwiftInteropInfo in target:
        interop_target = target
        interop_from_rule = True
    else:
        interop_target = None
        interop_from_rule = False

    # We don't break this loop early when we find a matching hint, because we
    # want to give an error message if there are two aspect hints that provide
    # `SwiftInteropInfo` (or if both the rule and an aspect hint do).
    found_overlay = False
    for hint in getattr(aspect_ctx.rule.attr, "aspect_hints", []):
        if SwiftOverlayCompileInfo in hint:
            found_overlay = True
        if SwiftInteropInfo in hint:
            if interop_target:
                if interop_from_rule:
                    fail(("Conflicting Swift interop info from the target " +
                          "'{target}' ({rule} rule) and the aspect hint " +
                          "'{hint}'. Only one is allowed.").format(
                        hint = str(hint.label),
                        target = str(target.label),
                        rule = aspect_ctx.rule.kind,
                    ))
                else:
                    fail(("Conflicting Swift interop info from aspect hints " +
                          "'{hint1}' and '{hint2}'. Only one is " +
                          "allowed.").format(
                        hint1 = str(interop_target.label),
                        hint2 = str(hint.label),
                    ))
            interop_target = hint

    if interop_target:
        return interop_target[SwiftInteropInfo]
    if found_overlay:
        # If no explicit interop hint was present but a `swift_overlay` was, we
        # still want that to imply the same thing as the `auto_module` hint
        # since it's the obvious right thing to do.
        return create_swift_interop_info()
    return None

def _legacy_objc_library_module_name(aspect_ctx):
    """Returns the `module_name` attribute for an `objc_library`.

    Args:
        aspect_ctx: The aspect context.

    Returns:
        The module name (a string) specified as an attribute on the
        `objc_library`. This may be `None`.
    """
    attr = aspect_ctx.rule.attr

    # TODO(b/195019413): Deprecate the use of these attributes and use
    # `swift_interop_hint` to customize `objc_*` targets' module names and
    # module maps.
    module_name = getattr(attr, "module_name", None)

    # TODO(b/195019413): Remove this when the `module_map` attribute is deleted.
    if getattr(attr, "module_map", None):
        fail(
            "The `module_map` attribute on `objc_library` is no longer " +
            "supported. Use `swift_interop_hint` instead to customize the " +
            "module map for a target.",
        )

    return module_name

def clang_module_name_for_target(
        *,
        aspect_ctx,
        feature_configuration = None,
        interop_info,
        target):
    """Returns the C/Objective-C module name for a target in an aspect context.

    Args:
        aspect_ctx: The aspect's context.
        feature_configuration: The Swift feature configuration, as returned by
            `swift_common.configure_features`, used when deriving a default
            module name from the target's label (for example, to account for the
            `swift.label_as_module_name` feature). If `None`, features enabled
            directly on the target, package, aspect hint, or command line are
            still respected.
        interop_info: The `SwiftInteropInfo` associated with the target, if any,
            as returned by `find_swift_interop_info`.
        target: The `Target` to which the aspect is being applied.

    Returns:
        The C/Objective-C module name (`str`) of the target, or `None` if the
        target does not define a C/Objective-C module or has its module
        suppressed.
    """
    if interop_info and interop_info.suppressed:
        return None

    if interop_info and interop_info.module_map:
        return interop_info.module_name

    compilation_context = interop_info.compilation_context if interop_info else None
    if not compilation_context and CcInfo in target:
        compilation_context = target[CcInfo].compilation_context

    # If a target doesn't have any headers, then don't generate a module map for
    # it. Such modules define nothing and only waste space on the compilation
    # command line and add more work for the compiler.
    if not compilation_context or (
        not compilation_context.direct_headers and
        not compilation_context.direct_textual_headers
    ):
        return None

    module_name = interop_info.module_name if interop_info else None
    if not module_name:
        if not interop_info and apple_common.Objc not in target:
            return None

        if aspect_ctx.rule.kind == "objc_library":
            module_name = _legacy_objc_library_module_name(aspect_ctx)

        # If it was an `objc_library` without an explicit module name, or it
        # was some other `Objc`-providing or `SwiftInteropInfo`-providing
        # target, derive the module name now.
        if not module_name:
            if not feature_configuration:
                requested_features = list(aspect_ctx.features)
                unsupported_features = list(aspect_ctx.disabled_features)
                if interop_info:
                    requested_features.extend(interop_info.requested_features)
                    unsupported_features.extend(
                        interop_info.unsupported_features,
                    )
                feature_configuration = struct(
                    _enabled_features = [
                        feature
                        for feature in requested_features
                        if feature not in unsupported_features
                    ],
                )
            module_name = derive_swift_module_name(
                target.label,
                feature_configuration = feature_configuration,
            )

    return module_name

def swift_module_names_for_target(
        *,
        aspect_ctx,
        feature_configuration = None,
        target):
    """Returns the Swift module names for a target in an aspect context.

    This function resolves the direct module names of a Swift or
    Swift-compatible C/Objective-C target using the same logic as
    `swift_clang_module_aspect`, allowing custom aspects to determine a target's
    module names without requiring `swift_clang_module_aspect` to be applied
    across the dependency graph.

    Aspects that call this function must include
    `required_swift_interop_aspect_hints_providers()` in their
    `required_aspect_hints_providers` attribute so that `swift_interop_hint` and
    `swift_overlay` targets are visible in `aspect_ctx.rule.attr.aspect_hints`.

    Args:
        aspect_ctx: The aspect's context.
        feature_configuration: The Swift feature configuration, as returned by
            `swift_common.configure_features`, used when deriving a default
            module name from the target's label (for example, to account for the
            `swift.label_as_module_name` feature). If `None`, features enabled
            directly on the target, package, aspect hint, or command line are
            still respected.
        target: The `Target` to which the aspect is being applied.

    Returns:
        A `list` of Swift module names (`str`) directly exposed by the target
        (their `source_name`s as they would be referenced in source code), or an
        empty list if the target does not represent any Swift-compatible modules
        or has its module suppressed.
    """
    if SwiftInfo in target:
        return [
            module.source_name
            for module in target[SwiftInfo].direct_modules
        ]

    interop_info = find_swift_interop_info(
        aspect_ctx = aspect_ctx,
        target = target,
    )
    if interop_info and interop_info.suppressed:
        return []

    module_names = []
    clang_module_name = clang_module_name_for_target(
        aspect_ctx = aspect_ctx,
        feature_configuration = feature_configuration,
        interop_info = interop_info,
        target = target,
    )
    if clang_module_name:
        module_names.append(clang_module_name)

    if interop_info:
        module_names.extend([
            module.source_name
            for swift_info in interop_info.direct_swift_infos
            for module in swift_info.direct_modules
        ])

    return module_names

def required_swift_interop_aspect_hints_providers():
    """Returns a list of provider sets required to inspect Swift aspect hints.

    Aspects that call `swift_module_names_for_target` must include the returned
    list in their `required_aspect_hints_providers` attribute so that
    `swift_interop_hint` and `swift_overlay` targets are visible in
    `aspect_ctx.rule.attr.aspect_hints`.

    This function returns a list so that it can be easily composed with other
    aspect hint provider sets if necessary. For example, an aspect could write:

    ```
    required_aspect_hints_providers = (
        required_swift_interop_aspect_hints_providers() + [other providers...]
    )
    ```

    Returns:
        A list of lists of providers that should be passed to the
        `required_aspect_hints_providers` argument of `aspect()`.
    """
    return [
        [SwiftInteropInfo],
        [SwiftOverlayCompileInfo],
    ]
