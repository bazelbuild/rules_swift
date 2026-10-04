"""Build the same Clang module through the default and two custom aspects."""

load("//swift:providers.bzl", "SwiftInfo")
load(
    "//swift:swift_clang_module_aspect.bzl",
    "make_swift_clang_module_aspect",
    "swift_clang_module_aspect",
)

custom_aspect_a = make_swift_clang_module_aspect(
    toolchain_type = Label("//toolchains:toolchain_type"),
)
custom_aspect_b = make_swift_clang_module_aspect(
    toolchain_type = Label("//toolchains:toolchain_type"),
)

def _collect_aspect_outputs_impl(ctx):
    files = []
    for dep in [ctx.attr.default, ctx.attr.custom_a, ctx.attr.custom_b]:
        for module in dep[SwiftInfo].direct_modules:
            if module.clang:
                files.append(module.clang.module_map)
                if module.clang.precompiled_module:
                    files.append(module.clang.precompiled_module)
    return [DefaultInfo(files = depset(files))]

collect_aspect_outputs = rule(
    implementation = _collect_aspect_outputs_impl,
    attrs = {
        "custom_a": attr.label(aspects = [custom_aspect_a], mandatory = True),
        "custom_b": attr.label(aspects = [custom_aspect_b], mandatory = True),
        "default": attr.label(aspects = [swift_clang_module_aspect], mandatory = True),
    },
)
