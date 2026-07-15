"""Test building for android."""

load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "//test/rules:android_validation_test.bzl",
    "android_apk_contents_test",
    "android_so_abi_test",
)

_ANDROID_CONFIG = {
    "//command_line_option:platforms": [
        str(Label("@rules_android//:arm64-v8a")),
    ],
}

android_command_line_test = make_action_command_line_test_rule(
    config_settings = _ANDROID_CONFIG,
)

def android_test_suite(name):
    """Test suite for the Android Swift SDK toolchain's compile/link actions.

    Args:
        name: The base name to be used in targets created by this macro.
    """
    all_tags = [name]

    # The Swift compile targets Android
    android_command_line_test(
        name = "{}_swiftcompile_targets_android".format(name),
        expected_argv = ["-target aarch64-linux-android28"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/android:jni_lib",
    )

    android_command_line_test(
        name = "{}_link_uses_ndk".format(name),
        expected_argv = [
            "--target=aarch64-linux-android28",
            "--sysroot",
            "-ldl",  # Comes from rules_android_ndk
            "-lm",  # Comes from rules_android_ndk
            "-lc",  # Comes from rules_android_ndk
            "-llog",  # This is a dependency of the Swift SDK
            "-Wl,-z,max-page-size=16384",  # Comes from rules_android_ndk
            "-Wl,--gc-sections",  # Comes from rules_android_ndk
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "//test/fixtures/android:jni_lib",
    )

    android_so_abi_test(
        name = "{}_jni_lib_abi".format(name),
        apk = "//test/fixtures/android:app.apk",
        jni_symbol = "Java_com_example_Fixture_value",
        needed_libraries = ["liblog.so"],
        not_needed_libraries = ["libc++_shared.so"],
        shared_library = "lib/arm64-v8a/libjni_lib.so",
        tags = all_tags,
    )

    android_apk_contents_test(
        name = "{}_apk_contents".format(name),
        apk = "//test/fixtures/android:app.apk",
        expected_entries = [
            "AndroidManifest.xml",
            "classes.dex",
            "lib/arm64-v8a/libjni_lib.so",
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
