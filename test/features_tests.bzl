"""Tests for various features that aren't large enough to need their own tests file."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

default_test = make_action_command_line_test_rule()
default_opt_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
    },
)

opt_no_wmo_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "//command_line_option:features": [
            "-swift.opt_uses_wmo",
        ],
    },
)

file_prefix_map_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.file_prefix_map",
        ],
    },
)

file_prefix_xcode_remap_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.file_prefix_map",
            "swift.remap_xcode_path",
        ],
    },
)

vfsoverlay_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.vfsoverlay",
        ],
    },
)

explicit_swift_module_map_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_explicit_swift_module_map",
        ],
    },
)

def features_test_suite(name):
    """Test suite for various features.

    Args:
      name: the base name to be used in things created by this macro
    """
    default_test(
        name = "{}_default_test".format(name),
        tags = [name],
        expected_argv = [
            "-emit-object",
            "-I$(BIN_DIR)/test/fixtures/basic",
        ],
        not_expected_argv = [
            "-file-prefix-map",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/basic:second",
    )

    file_prefix_map_test(
        name = "{}_file_prefix_map_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    file_prefix_xcode_remap_test(
        name = "{}_file_prefix_xcode_remap_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-file-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=DEVELOPER_DIR",
        ],
        target_compatible_with = ["@platforms//os:macos"],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    default_opt_test(
        name = "{}_default_opt_test".format(name),
        tags = [name],
        expected_argv = ["-emit-object", "-O", "-whole-module-optimization"],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    opt_no_wmo_test(
        name = "{}_opt_no_wmo_test".format(name),
        tags = [name],
        expected_argv = ["-emit-object", "-O"],
        not_expected_argv = ["-whole-module-optimization"],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    vfsoverlay_test(
        name = "{}_vfsoverlay_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xfrontend -vfsoverlay$(BIN_DIR)/test/fixtures/basic/second.vfsoverlay.yaml",
            "-I/__build_bazel_rules_swift/swiftmodules",
        ],
        not_expected_argv = [
            "-I$(BIN_DIR)/test/fixtures/basic",
            "-explicit-swift-module-map-file",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/basic:second",
    )

    explicit_swift_module_map_test(
        name = "{}_explicit_swift_module_map_test".format(name),
        tags = [name],
        expected_argv = [
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/basic/second.swift-explicit-module-map.json",
        ],
        not_expected_argv = [
            "-I$(BIN_DIR)/test/fixtures/basic",
            "-I/__build_bazel_rules_swift/swiftmodules",
            "-Xfrontend -vfsoverlay$(BIN_DIR)/test/fixtures/basic/second.vfsoverlay.yaml",
        ],
        mnemonic = "SwiftCompile",
        target_under_test = "@build_bazel_rules_swift//test/fixtures/basic:second",
    )
