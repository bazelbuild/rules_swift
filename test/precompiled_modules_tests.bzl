"""Tests for the default precompiled-modules injection."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

_precompiled_modules_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_c_modules",
            "swift.emit_c_module",
            "swift.add_default_precompiled_modules",
        ],
    },
)

_explicit_precompiled_modules_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_c_modules",
            "swift.emit_c_module",
            "-swift.add_default_precompiled_modules",
        ],
    },
)

def precompiled_modules_test_suite(name, tags = []):
    """Test precompiled modules behavior.

    Args:
        name: The base name to be used for targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    _precompiled_modules_test(
        name = "{}_use_c_modules_flags_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:hello",
        expected_argv = [
            "-Xcc -fno-implicit-modules",
            "-Xcc -fno-implicit-module-maps",
        ],
    )

    _precompiled_modules_test(
        name = "{}_default_precompiled_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:hello",
        expected_argv = [
            "-fmodule-file=Foundation",
            "-fmodule-file=SwiftShims",
        ],
    )

    _explicit_precompiled_modules_test(
        name = "{}_no_default_precompiled_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:hello",
        not_expected_argv = [
            "-fmodule-file=Foundation",
            "-fmodule-file=SwiftShims",
        ],
    )

    _explicit_precompiled_modules_test(
        name = "{}_explicit_deps_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:hello_with_explicit_deps_bin",
        expected_argv = [
            "-fmodule-file=Foundation",
            "-fmodule-file=SwiftShims",
        ],
    )

    _precompiled_modules_test(
        name = "{}_compiler_plugin_default_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:stub_plugin",
        expected_argv = [
            "-fmodule-file=Foundation",
            "-fmodule-file=SwiftShims",
        ],
    )

    _precompiled_modules_test(
        name = "{}_c_module_imports_pcms_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:c_module_imports",
        expected_argv = [
            "-fmodule-file=Compression",
            "-fmodule-file=SQLite3",
            "-fmodule-file=zlib",
        ],
    )

    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "//test/fixtures/precompiled_modules:hello",
            "//test/fixtures/precompiled_modules:hello_with_explicit_deps_transitioned",
            "//test/fixtures/precompiled_modules:objc_interop_bin_transitioned",
            "//test/fixtures/precompiled_modules:objc_interop_implicit_bin_transitioned",
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
