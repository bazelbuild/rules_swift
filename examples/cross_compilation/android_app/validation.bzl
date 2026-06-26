"""Validates the built Android JNI `.so` with the NDK's `llvm-readelf`.

The assertions run at build time (so the NDK `llvm-readelf` is reached through the
resolved Android cc toolchain) and are surfaced as a test with `build_test`. They
guard the things a `build_test` alone can't see: that the JNI entry point is
actually exported in the dynamic symbol table, that the `.so` is an AArch64 ELF,
and that it links `libc++_shared.so` dynamically (so the APK must ship it).
"""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")

# Incoming transition so the rule (and its `.so` dep) resolve for Android, which
# makes `find_cc_toolchain` return the NDK toolchain whose files include
# `llvm-readelf`.
def _android_transition_impl(_settings, _attr):
    return {"//command_line_option:platforms": "@rules_android//:arm64-v8a"}

_android_transition = transition(
    implementation = _android_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _android_so_abi_check_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    readelf = None
    for f in cc_toolchain.all_files.to_list():
        if f.basename == "llvm-readelf":
            readelf = f
            break
    if not readelf:
        fail("llvm-readelf was not found in the resolved Android cc toolchain.")

    so = ctx.file.shared_library
    marker = ctx.actions.declare_file(ctx.label.name + ".ok")
    command = """
set -u
header=$('{readelf}' -h '{so}')
case "$header" in
  *AArch64*) ;;
  *) echo 'error: {so} is not an AArch64 ELF' >&2; exit 1 ;;
esac
dynamic=$('{readelf}' -d '{so}')
case "$dynamic" in
  *libc++_shared.so*) ;;
  *) echo 'error: {so} does not list libc++_shared.so in NEEDED' >&2; exit 1 ;;
esac
dynsyms=$('{readelf}' --dyn-syms '{so}')
case "$dynsyms" in
  *{sym}*) ;;
  *) echo 'error: JNI symbol {sym} is not exported in the .dynsym of {so}' >&2; exit 1 ;;
esac
touch '{marker}'
""".format(
        readelf = readelf.path,
        so = so.path,
        sym = ctx.attr.jni_symbol,
        marker = marker.path,
    )
    ctx.actions.run_shell(
        inputs = depset([so], transitive = [cc_toolchain.all_files]),
        outputs = [marker],
        command = command,
        mnemonic = "AndroidSoAbiCheck",
        progress_message = "Validating Android JNI .so %s" % so.short_path,
    )
    return [DefaultInfo(files = depset([marker]))]

android_so_abi_check = rule(
    implementation = _android_so_abi_check_impl,
    cfg = _android_transition,
    attrs = {
        "shared_library": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The `swift_binary(linkshared = True)` JNI library to inspect.",
        ),
        "jni_symbol": attr.string(
            mandatory = True,
            doc = "The `@_cdecl` JNI entry point expected in the `.so`'s `.dynsym`.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = use_cc_toolchain(),
)

def _android_apk_contents_check_impl(ctx):
    apk = ctx.file.apk
    marker = ctx.actions.declare_file(ctx.label.name + ".ok")
    checks = "\n".join([
        """case "$listing" in
  *'{entry}'*) ;;
  *) echo 'error: APK is missing {entry}' >&2; exit 1 ;;
esac""".format(entry = entry)
        for entry in ctx.attr.expected_entries
    ])
    ctx.actions.run_shell(
        inputs = [apk],
        outputs = [marker],
        tools = [ctx.executable._zipper],
        command = """
set -u
listing=$('{zipper}' v '{apk}')
{checks}
touch '{marker}'
""".format(
            zipper = ctx.executable._zipper.path,
            apk = apk.path,
            checks = checks,
            marker = marker.path,
        ),
        mnemonic = "AndroidApkContentsCheck",
        progress_message = "Validating APK contents of %s" % apk.short_path,
    )
    return [DefaultInfo(files = depset([marker]))]

android_apk_contents_check = rule(
    implementation = _android_apk_contents_check_impl,
    attrs = {
        "apk": attr.label(
            allow_single_file = [".apk"],
            mandatory = True,
            doc = "The APK whose entries to assert.",
        ),
        "expected_entries": attr.string_list(
            mandatory = True,
            doc = "Zip entry paths that must be present in the APK.",
        ),
        "_zipper": attr.label(
            default = "@bazel_tools//tools/zip:zipper",
            executable = True,
            cfg = "exec",
        ),
    },
)
