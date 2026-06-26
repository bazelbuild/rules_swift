"""Tests that the Android Swift SDK toolchain links through the NDK cc toolchain
with the right target triple."""

load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "//test/rules:action_inputs_test.bzl",
    "make_action_inputs_test_rule",
)

# Build the target under test for Android (the SDK toolchain + the NDK cc
# toolchain resolve from these constraints). The platform label is resolved to
# its canonical form here so the transition (applied in the analysistest rule's
# own repository) still points at this repository's fixture.
_ANDROID_CONFIG = {
    "//command_line_option:platforms": [
        str(Label("//test/fixtures/android:android_arm64")),
    ],
}

android_command_line_test = make_action_command_line_test_rule(
    config_settings = _ANDROID_CONFIG,
)

android_inputs_test = make_action_inputs_test_rule(
    config_settings = _ANDROID_CONFIG,
)

def android_test_suite(name, tags = []):
    """Test suite for the Android Swift SDK toolchain's compile/link actions.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # The Swift compile targets the Android triple.
    android_command_line_test(
        name = "{}_swiftcompile_targets_android".format(name),
        expected_argv = ["-target aarch64-linux-android"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/android:jni_lib",
    )

    # The link runs the NDK clang for the Android target (the `28` is the
    # `android.ndk(api_level = ...)` from MODULE.bazel), against the NDK sysroot,
    # and links libc++ as the shared `libc++_shared.so`.
    android_command_line_test(
        name = "{}_link_uses_ndk".format(name),
        expected_argv = [
            "--target=aarch64-linux-android28",
            "--sysroot",
            "-lstdc++",
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/android:jni_lib",
    )

    # The NDK's libc++_shared.so is staged into the link so a downstream APK can
    # package it next to the Swift `.so`.
    android_inputs_test(
        name = "{}_link_stages_libcxx_shared".format(name),
        expected_inputs = ["libc++_shared.so"],
        mnemonic = "CppLink",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/android:jni_lib",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
