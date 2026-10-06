"""Fixture for strict include paths carried only by SwiftInfo."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//swift:providers.bzl", "SwiftInfo", "create_clang_module_inputs", "create_swift_module_context")

def _strict_include_module_impl(ctx):
    return [SwiftInfo(
        modules = [create_swift_module_context(
            name = ctx.label.name,
            clang = create_clang_module_inputs(
                compilation_context = cc_common.create_compilation_context(),
                module_map = None,
                strict_includes = depset(ctx.attr.strict_includes),
            ),
        )],
        swift_infos = [dep[SwiftInfo] for dep in ctx.attr.deps],
    )]

strict_include_module = rule(
    implementation = _strict_include_module_impl,
    attrs = {
        "deps": attr.label_list(providers = [SwiftInfo]),
        "strict_includes": attr.string_list(),
    },
)
