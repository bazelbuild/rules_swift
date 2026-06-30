"""Android build artifact validation tests."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

def _android_transition_impl(_settings, _attr):
    return {"//command_line_option:platforms": "@rules_android//:arm64-v8a"}

_android_transition = transition(
    implementation = _android_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _rlocationpath(ctx, label, targets):
    return ctx.expand_location(
        "$(rlocationpath {})".format(label),
        targets = targets,
    )

def _toolchain_file_runfiles_path(ctx, file):
    short_path = file.short_path
    if short_path.startswith("../"):
        return short_path[3:]
    return "{}/{}".format(ctx.workspace_name, short_path)

def _find_tool(cc_toolchain, basename):
    for f in cc_toolchain.all_files.to_list():
        if f.basename == basename:
            return f
    fail("{} was not found in the resolved Android cc toolchain.".format(basename))

def _android_so_abi_test_impl(ctx):
    cc_toolchain = ctx.attr._cc_toolchain[0][cc_common.CcToolchainInfo]
    nm = _find_tool(cc_toolchain, "llvm-nm")
    readelf = _find_tool(cc_toolchain, "llvm-readelf")

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = ctx.file._runner_script,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = [ctx.file.apk, ctx.file._runner_script, ctx.executable._zipper],
                transitive_files = cc_toolchain.all_files,
            ).merge_all([
                ctx.attr._runfiles.default_runfiles,
                ctx.attr._zipper.default_runfiles,
            ]),
        ),
        testing.TestEnvironment({
            "ANDROID_APK": _rlocationpath(ctx, ctx.attr.apk[0].label, ctx.attr.apk),
            "ANDROID_JNI_SYMBOL": ctx.attr.jni_symbol,
            "ANDROID_NEEDED_LIBRARIES": "\n".join(ctx.attr.needed_libraries),
            "ANDROID_NM": _toolchain_file_runfiles_path(ctx, nm),
            "ANDROID_NOT_NEEDED_LIBRARIES": "\n".join(ctx.attr.not_needed_libraries),
            "ANDROID_READELF": _toolchain_file_runfiles_path(ctx, readelf),
            "ANDROID_SHARED_LIBRARY": ctx.attr.shared_library,
            "ANDROID_ZIPPER": _rlocationpath(ctx, ctx.attr._zipper.label, [ctx.attr._zipper]),
        }),
    ]

android_so_abi_test = rule(
    implementation = _android_so_abi_test_impl,
    attrs = {
        "apk": attr.label(
            allow_single_file = [".apk"],
            cfg = _android_transition,
            mandatory = True,
            doc = "The APK containing the JNI library to inspect.",
        ),
        "jni_symbol": attr.string(
            mandatory = True,
            doc = "The JNI entry point expected in the shared library's dynamic symbols.",
        ),
        "needed_libraries": attr.string_list(
            doc = "Shared library names expected in the ELF dynamic NEEDED entries.",
        ),
        "not_needed_libraries": attr.string_list(
            doc = "Shared library names not expected in the ELF dynamic NEEDED entries.",
        ),
        "_cc_toolchain": attr.label(
            cfg = _android_transition,
            default = "@rules_cc//cc:current_cc_toolchain",
        ),
        "shared_library": attr.string(
            mandatory = True,
            doc = "The APK entry path of the JNI shared library to inspect.",
        ),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
        "_runner_script": attr.label(
            allow_single_file = True,
            default = "//test/rules:android_so_abi_test.sh",
        ),
        "_zipper": attr.label(
            default = "@bazel_tools//tools/zip:zipper",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
)

def _android_apk_contents_test_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = ctx.file._runner_script,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = executable,
            runfiles = ctx.runfiles(
                files = [ctx.file.apk, ctx.file._runner_script, ctx.executable._zipper],
            ).merge_all([
                ctx.attr._runfiles.default_runfiles,
                ctx.attr._zipper.default_runfiles,
            ]),
        ),
        testing.TestEnvironment({
            "ANDROID_APK": _rlocationpath(ctx, ctx.attr.apk[0].label, ctx.attr.apk),
            "ANDROID_EXPECTED_ENTRIES": "\n".join(ctx.attr.expected_entries),
            "ANDROID_ZIPPER": _rlocationpath(ctx, ctx.attr._zipper.label, [ctx.attr._zipper]),
        }),
    ]

android_apk_contents_test = rule(
    implementation = _android_apk_contents_test_impl,
    attrs = {
        "apk": attr.label(
            allow_single_file = [".apk"],
            cfg = _android_transition,
            mandatory = True,
            doc = "The APK whose entries to assert.",
        ),
        "expected_entries": attr.string_list(
            mandatory = True,
            doc = "Zip entry paths that must be present in the APK.",
        ),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
        "_runner_script": attr.label(
            allow_single_file = True,
            default = "//test/rules:android_apk_contents_test.sh",
        ),
        "_zipper": attr.label(
            default = "@bazel_tools//tools/zip:zipper",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
)
