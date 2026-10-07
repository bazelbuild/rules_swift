"""Exercises multiple Swift Clang module aspects on one target."""

load("//swift:providers.bzl", "SwiftInfo")
load("//swift:swift_clang_module_aspect.bzl", "make_swift_clang_module_aspect", "swift_clang_module_aspect")

_toolchain_type = Label("//toolchains:toolchain_type")
custom_aspect_one = make_swift_clang_module_aspect(toolchain_type = _toolchain_type)
custom_aspect_two = make_swift_clang_module_aspect(toolchain_type = _toolchain_type)

def _collect_outputs_impl(ctx):
    outputs = []
    for dep in [ctx.attr.default, ctx.attr.custom_one, ctx.attr.custom_two]:
        for module in dep[SwiftInfo].direct_modules:
            outputs.append(module.clang.module_map)
            if module.clang.precompiled_module:
                outputs.append(module.clang.precompiled_module)
    return [DefaultInfo(files = depset(outputs))]

collect_outputs = rule(
    attrs = {
        "default": attr.label(aspects = [swift_clang_module_aspect]),
        "custom_one": attr.label(aspects = [custom_aspect_one]),
        "custom_two": attr.label(aspects = [custom_aspect_two]),
    },
    implementation = _collect_outputs_impl,
)
