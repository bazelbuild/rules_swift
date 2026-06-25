"""A rule that selects a single Android NDK runtime library from the toolchain.

The Android NDK's shared C++ runtime (`libc++_shared.so`) must be packaged into
any APK that contains Swift (or other NDK C++) code. This rule selects it out of
the resolved C++ (cc) toolchain's files, so a consumer can reference it for APK
packaging without naming the NDK repository or build host. Build it for an
Android platform so the Android cc toolchain (e.g. `@androidndk//:all`) is
resolved.
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")

def _select_android_runtime_lib_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    suffix = "/usr/lib/{}/{}".format(ctx.attr.triple, ctx.attr.basename)
    matches = [
        f
        for f in cc_toolchain.all_files.to_list()
        if f.path.endswith(suffix)
    ]
    if len(matches) != 1:
        fail("Expected exactly one `{}` under `usr/lib/{}` in the Android cc toolchain, found: {}".format(
            ctx.attr.basename,
            ctx.attr.triple,
            [f.path for f in matches],
        ))
    return [DefaultInfo(files = depset(matches))]

select_android_runtime_lib = rule(
    implementation = _select_android_runtime_lib_impl,
    attrs = {
        "basename": attr.string(
            default = "libc++_shared.so",
            doc = "The runtime library file name to select.",
        ),
        "triple": attr.string(
            mandatory = True,
            doc = "The Android target triple, e.g. `aarch64-linux-android`.",
        ),
    },
    toolchains = use_cc_toolchain(),
    doc = """\
Selects a single runtime library (by default `libc++_shared.so`) for an Android
target triple out of the resolved C++ toolchain's files, exposing it as a
one-file target for APK packaging. Build it for an Android platform.
""",
)
