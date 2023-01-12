"""Return the .swiftmodule file from a swift_library for testing"""

load("//swift:swift.bzl", "SwiftInfo")

def _impl(ctx):
    modules = ctx.attr.lib[SwiftInfo].direct_modules
    if len(modules) != 1:
        fail("unexpected number of modules: {}".format(len(modules)))

    return [DefaultInfo(files = depset([modules[0].swift.swiftmodule]))]

get_swiftmodule = rule(
    implementation = _impl,
    attrs = {
        "lib": attr.label(providers = [SwiftInfo]),
    },
)
