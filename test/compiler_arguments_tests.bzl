"""Tests for various compiler arguments."""

load(
    "//test/rules:action_command_line_test.bzl",
    "action_command_line_test",
    "make_action_command_line_test_rule",
)

split_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.split_derived_files_generation",
        ],
    },
)

thin_lto_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.thin_lto",
        ],
    },
)

full_lto_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.full_lto",
        ],
    },
)

swiftcopt_swift_version_test = make_action_command_line_test_rule(
    config_settings = {
        str(Label("//swift:copt")): [
            "-swift-version",
            "4.2",
        ],
    },
)

swiftcopt_single_threaded_wmo_test = make_action_command_line_test_rule(
    config_settings = {
        str(Label("//swift:copt")): [
            "-whole-module-optimization",
            "-num-threads",
            "0",
        ],
    },
)

def compiler_arguments_test_suite(name, tags = []):
    """Test suite for various command line flags passed to Swift compiles.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    action_command_line_test(
        name = "{}_no_package_by_default".format(name),
        not_expected_argv = ["-package-name"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    action_command_line_test(
        name = "{}_lib_with_package".format(name),
        expected_argv = ["-package-name lib"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:lib_package_name",
    )

    action_command_line_test(
        name = "{}_bin_with_package".format(name),
        expected_argv = ["-package-name bin"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:bin_package_name",
    )

    action_command_line_test(
        name = "{}_test_with_package".format(name),
        expected_argv = ["-package-name test"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:test_package_name",
    )

    split_test(
        name = "{}_split_lib_with_package".format(name),
        expected_argv = ["-package-name lib"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:lib_package_name",
    )

    split_test(
        name = "{}_split_module_with_package".format(name),
        expected_argv = ["-package-name lib"],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:lib_package_name",
    )

    thin_lto_test(
        name = "{}_thin_lto".format(name),
        expected_argv = ["-lto=llvm-thin"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:bin",
    )

    full_lto_test(
        name = "{}_full_lto".format(name),
        expected_argv = ["-lto=llvm-full"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:bin",
    )

    action_command_line_test(
        name = "{}_default_swift_version".format(name),
        expected_argv = ["-swift-version 5"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    split_test(
        name = "{}_default_swift_version_in_derive_files".format(name),
        expected_argv = ["-swift-version 5"],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    action_command_line_test(
        name = "{}_copts_overrides_default_swift_version".format(name),
        expected_argv = [
            "-swift-version 5",
            "-swift-version 4.2",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:lib_with_swift_version_copt",
    )

    swiftcopt_swift_version_test(
        name = "{}_swiftcopt_overrides_default_swift_version".format(name),
        expected_argv = [
            "-swift-version 5",
            "-swift-version 4.2",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    swiftcopt_single_threaded_wmo_test(
        name = "{}_swiftcopt_single_threaded_wmo".format(name),
        expected_argv = [
            "-whole-module-optimization",
            "-num-threads 0",
        ],
        mnemonic = "SwiftCompile",
        not_expected_argv = ["-num-threads 12"],
        tags = all_tags,
        target_under_test = "//test/fixtures/compiler_arguments:no_package_name",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
