"""Fixtures for special module-map handling and existing precompile callers."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:providers.bzl", "SwiftInfo", "create_swift_module_context")
load("//swift:swift_clang_module_aspect.bzl", "swift_clang_module_aspect")
load("//swift:swift_common.bzl", "swift_common")

def _cc_inc_library_impl(ctx):
    # Match the public-header and transitive-context shape of cc_inc_library.
    return [CcInfo(compilation_context = cc_common.create_compilation_context(
        headers = depset(ctx.files.hdrs, transitive = [dep[CcInfo].compilation_context.headers for dep in ctx.attr.deps]),
        direct_public_headers = ctx.files.hdrs,
    ))]

cc_inc_library = rule(
    implementation = _cc_inc_library_impl,
    attrs = {
        "hdrs": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [CcInfo]),
    },
)

def _legacy_precompile_impl(ctx):
    toolchains = swift_common.find_all_toolchains(ctx)
    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
        toolchains = toolchains,
    )
    compilation_context = cc_common.create_compilation_context(
        headers = depset(ctx.files.hdrs, transitive = [dep[CcInfo].compilation_context.headers for dep in ctx.attr.deps]),
        direct_public_headers = ctx.files.hdrs,
    )
    swift_infos = [dep[SwiftInfo] for dep in ctx.attr.deps]

    # Deliberately omit unchecked_include_headers to exercise existing callers.
    result = swift_common.precompile_clang_module(
        actions = ctx.actions,
        cc_compilation_context = compilation_context,
        feature_configuration = feature_configuration,
        module_map_file = ctx.file.module_map,
        module_name = "Legacy",
        swift_infos = swift_infos,
        target_name = ctx.label.name,
        toolchains = toolchains,
    )
    return [
        DefaultInfo(files = depset([result.clang_module.precompiled_module])),
        CcInfo(compilation_context = compilation_context),
        SwiftInfo(
            modules = [create_swift_module_context(
                name = "Legacy",
                clang = result.clang_module,
            )],
            swift_infos = swift_infos,
        ),
    ]

legacy_precompile = rule(
    implementation = _legacy_precompile_impl,
    attrs = {
        "hdrs": attr.label_list(allow_files = True),
        "module_map": attr.label(allow_single_file = True),
        "deps": attr.label_list(providers = [CcInfo], aspects = [swift_clang_module_aspect]),
    },
    fragments = ["cpp"],
    toolchains = swift_common.use_all_toolchains(),
)

def _pcm_files_impl(ctx):
    return [DefaultInfo(files = depset([
        module.clang.precompiled_module
        for dep in ctx.attr.deps
        for module in dep[SwiftInfo].transitive_modules.to_list()
        if module.clang and module.clang.precompiled_module
    ]))]

pcm_files = rule(
    implementation = _pcm_files_impl,
    attrs = {
        "deps": attr.label_list(aspects = [swift_clang_module_aspect]),
    },
)
