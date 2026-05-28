"""Tests for Swift layering checks."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)

layering_check_swift_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.layering_check_swift",
        ],
    },
)

def layering_check_test_suite(name, tags = []):
    """Tests Swift layering-check behavior.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    action_command_line_test(
        name = "{}_layering_check_swift_disabled_by_default".format(name),
        not_expected_argv = [
            "-Xwrapped-swift=-layering-check-deps-modules",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    layering_check_swift_test(
        name = "{}_layering_check_swift_enabled".format(name),
        expected_argv = [
            "-Xwrapped-swift=-layering-check-deps-modules=$(BIN_DIR)/test/fixtures/compiler_arguments/no_package_name.deps-module-mapping",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "//test/fixtures/layering_check:foundation_consumer",
            "//test/fixtures/layering_check:self_importing_consumer",
            "//test/fixtures/module_mapping:MySDK_with_mapping_and_layering_check",
        ],
        tags = all_tags,
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
    )

    build_test(
        name = "{}_apple_build_test".format(name),
        targets = [
            "//test/fixtures/layering_check:foundation_consumer_default_precompiled_modules",
        ],
        tags = all_tags,
        target_compatible_with = select({
            "@build_bazel_apple_support//configs:apple": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
