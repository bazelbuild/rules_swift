"""
objc_library wraps an upstream rules_cc objc_library to better support module maps across
transitive interop layers.

This rule extension takes a module map, either by attr, interop hint, or from creating a
new one, and forces itself to propagate to downstream dependencies.
"""

load("@cc_compatibility_proxy//:proxy.bzl", _upstream_objc_library = "objc_library")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:module_name.bzl", "derive_swift_module_name")
load("//swift:swift_interop_info.bzl", "create_swift_interop_info")

# buildifier: disable=bzl-visibility
load("//swift/internal:feature_names.bzl", "SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD", "SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS")

# buildifier: disable=bzl-visibility
load("//swift/internal:features.bzl", "configure_features", "is_feature_enabled")

# buildifier: disable=bzl-visibility
load("//swift/internal:module_maps.bzl", "write_module_map")

# buildifier: disable=bzl-visibility
load("//swift/internal:toolchain_utils.bzl", "get_swift_toolchain", "use_swift_toolchain")

def _objc_library_impl(ctx):
    requested_features = ctx.features
    swift_toolchain = get_swift_toolchain(ctx)
    unsupported_features = ctx.disabled_features
    feature_configuration = configure_features(
        ctx = ctx,
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
        unsupported_features = unsupported_features,
    )

    providers = ctx.super()
    cc_info, swift_info, swift_interop_info, passthrough_providers = _get_providers(providers)

    module_map, new_swift_interop_info = _derive_module(
        ctx,
        cc_info = cc_info,
        feature_configuration = feature_configuration,
        requested_features = requested_features,
        swift_info = swift_info,
        swift_interop_info = swift_interop_info,
        unsupported_features = unsupported_features,
    )
    if not module_map:
        fail("expected module map")

    new_cc_info = cc_common.merge_cc_infos(
        direct_cc_infos = [
            CcInfo(
                compilation_context = cc_common.create_compilation_context(
                    headers = depset([module_map]),
                    includes = depset([module_map.dirname]),
                ),
            ),
        ],
        cc_infos = [cc_info],
    )

    return passthrough_providers + [new_cc_info] + ([new_swift_interop_info] if new_swift_interop_info else [])

def _get_providers(providers):
    """
    Iterates the list of providers from the parent rule and extracts the necessary providers for the child implementation.

    CcInfo and SwiftInteropInfo (if present) are removed from the resultant list, and the rest are returned as passthrough providers

    Args:
        providers: A list of providers from the parent rule.

    Returns:
        A tuple of a CcInfo from the parent (omitted from the passthrough providers), an optional SwiftInfo
        from the parent, an optional SwiftInteropInfo from the parent (if present, and omitted from the
        passthrough providers), and a list of all other providers from the original list
    """
    cc_info = None
    swift_info = None
    swift_interop_info = None
    passthrough_providers = []

    for provider in providers:
        if type(provider) == "CcInfo" or \
           (type(provider) == "struct" and hasattr(provider, "compilation_context")):  # NOTE: Will require an update when this provider moves to starlark
            cc_info = provider
        elif type(provider) == "SwiftInfo":
            swift_info = provider
            passthrough_providers.append(provider)
        elif type(provider) == "SwiftInteropInfo":
            swift_interop_info = provider
        else:
            passthrough_providers.append(provider)

    if not cc_info:
        fail("CcInfo expected in providers list, got None")

    return cc_info, swift_info, swift_interop_info, passthrough_providers

def _derive_module(
        ctx,
        *,
        cc_info,
        feature_configuration,
        requested_features,
        swift_info,
        swift_interop_info,
        unsupported_features):
    """
    Constructs module map info about the parent rule.

    Args:
        ctx: The rule context
        cc_info: CcInfo of the parent rule
        feature_configuration: A Swift feature configuration.
        requested_features: The list of features to be enabled. This is
            typically obtained using the `ctx.features` field in a rule
            implementation function.
        swift_info: Optional. SwiftInfo of the parent rule, if any.
        swift_interop_info: Optional. SwiftInteropInfo of the parent rule, if any.
        unsupported_features: The list of features that are unsupported by the
            current rule. This is typically obtained using the
            `ctx.disabled_features` field in a rule implementation function.

    Returns:
        A tuple of a File pointed at the new or existing module map, and a
        SwiftInteropInfo to be returned as a provider and used by the
        swift_clang_module_aspect.
    """
    if swift_info and swift_info.direct_modules:
        direct_modules = swift_info.direct_modules
    else:
        direct_modules = []

    if ctx.attr.module_map:
        module_map = ctx.attr.module_map
        new_swift_interop_info = swift_interop_info
    elif swift_interop_info and swift_interop_info.module_map:
        module_map = swift_interop_info.module_map
        new_swift_interop_info = swift_interop_info
    elif direct_modules and len(direct_modules) == 1 and hasattr(direct_modules[0], "clang"):
        module_map = direct_modules[0].clang.module_map
        new_swift_interop_info = swift_interop_info
    else:
        if ctx.attr.module_name:
            module_name = ctx.attr.module_name
        elif swift_interop_info and swift_interop_info.module_name:
            module_name = swift_interop_info.module_name
        else:
            module_name = derive_swift_module_name(ctx.label)

        dependent_module_names = [
            module.name
            for module in direct_modules
            if module.clang
        ]

        module_map, new_swift_interop_info = _write_module_map(
            actions = ctx.actions,
            cc_info = cc_info,
            dependent_module_names = dependent_module_names,
            feature_configuration = feature_configuration,
            label = ctx.label,
            module_name = module_name,
            swift_info = swift_info,
            requested_features = requested_features,
            swift_interop_info = swift_interop_info,
            unsupported_features = unsupported_features,
        )

    return module_map, new_swift_interop_info

def _write_module_map(
        *,
        actions,
        cc_info,
        dependent_module_names,
        feature_configuration,
        label,
        module_name,
        requested_features,
        swift_info,
        swift_interop_info,
        unsupported_features):
    """
    Generates the module map file for the given target.

    Args:
        actions: The object used to register actions.
        cc_info: CcInfo for the parent rule
        dependent_module_names: A `list` of names of Clang modules that are
            direct dependencies of the target whose module map is being written.
        feature_configuration: A Swift feature configuration.
        label: The label of the rule
        module_name: The name of the module.
        requested_features: The list of features to be enabled. This is
            typically obtained using the `ctx.features` field in a rule
            implementation function.
        swift_info: Optional. SwiftInfo of the parent rule, if any.
        swift_interop_info: Optional. SwiftInteropInfo of the parent rule, if any.
        unsupported_features: The list of features that are unsupported by the
            current rule. This is typically obtained using the
            `ctx.disabled_features` field in a rule implementation function.

    Returns:
        A tuple of a `File` representing the generated module map, and a new
        SwiftInteropInfo (constructed out of the old one if provided)
    """
    workspace_relative = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD,
    )
    exclude_private_headers = is_feature_enabled(
        feature_configuration = feature_configuration,
        feature_name = SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS,
    )

    def _path_sorting_key(file):
        return file.path

    public_headers = []
    private_headers = []
    textual_headers = []
    exclude_headers = []

    if not exclude_private_headers:
        private_headers = cc_info.compilation_context.direct_private_headers

    public_headers = sorted(
        cc_info.compilation_context.direct_public_headers,
        key = _path_sorting_key,
    )
    textual_headers = sorted(
        cc_info.compilation_context.direct_textual_headers,
        key = _path_sorting_key,
    )

    if swift_interop_info:
        exclude_headers = sorted(swift_interop_info.exclude_headers, key = _path_sorting_key)

    module_map = actions.declare_file(
        "{}_modulemap/_/module.modulemap".format(label.name),
    )

    write_module_map(
        actions = actions,
        module_map_file = module_map,
        module_name = module_name,
        dependent_module_names = dependent_module_names,
        exclude_headers = exclude_headers,
        exported_module_ids = ["*"],
        public_headers = public_headers,
        public_textual_headers = textual_headers,
        private_headers = sorted(private_headers, key = _path_sorting_key),
        workspace_relative = workspace_relative,
    )

    return module_map, create_swift_interop_info(
        exclude_headers = exclude_headers,
        module_map = module_map,
        module_name = module_name,
        requested_features = requested_features,
        swift_infos = [swift_info] if swift_info else [],
        unsupported_features = unsupported_features,
    )

_objc_library_rule = rule(
    implementation = _objc_library_impl,
    parent = _upstream_objc_library,
    toolchains = use_swift_toolchain(),
    doc = """\
An objc_library that takes a module map, either by attr, interop hint, or from creating a new one, and
forces itself to propagate to downstream dependencies.
""",
)

def objc_library(
        *,
        name,
        enable_modules = True,
        **kwargs):
    """
    Thin wrapper around objc_library that enables Clang modules and generates a \
    well-propagated module_map if one is not provided.

    Args:
        name: Name of the target
        enable_modules: Enable Clang modules within the compilation unit
        **kwargs: Any other attrs of objc_library
    """
    _objc_library_rule(
        name = name,
        enable_modules = enable_modules,
        **kwargs
    )
