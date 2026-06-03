"""Tests for the default precompiled-modules injection."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//test/fixtures/precompiled_modules:cross_platform.bzl",
    "CROSS_PLATFORM_TARGETS",
)
load("//test/hermetic_pcm:xcode_version_at_least.bzl", "xcode_version_at_least")
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

    xcode_version_at_least(
        name = "xcode_at_least_26_4",
        minimum_version = "26.4",
    )

    native.config_setting(
        name = "has_testing_appkit_overlay",
        flag_values = {":xcode_at_least_26_4": "True"},
    )

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
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:hello",
        expected_argv = [
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/precompiled_modules/hello.swift-system-explicit-module-map.json",
        ],
        not_expected_argv = [
            "-fmodule-file=Foundation",
            "-fmodule-file=SwiftShims",
        ],
    )

    _explicit_precompiled_modules_test(
        name = "{}_no_default_precompiled_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_compatible_with = select({
            "@build_bazel_apple_support//configs:apple": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:hello",
        expected_argv = [
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/precompiled_modules/hello.swift-system-explicit-module-map.json",
        ],
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
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/precompiled_modules/hello_with_explicit_deps_bin.swift-system-explicit-module-map.json",
        ],
        not_expected_argv = [
            "-fmodule-file=Foundation",
            "-fmodule-file=SwiftShims",
        ],
    )

    _precompiled_modules_test(
        name = "{}_compiler_plugin_default_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:stub_plugin",
        expected_argv = [
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/precompiled_modules/stub_plugin.swift-system-explicit-module-map.json",
        ],
        not_expected_argv = [
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
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/precompiled_modules/c_module_imports.swift-system-explicit-module-map.json",
        ],
        not_expected_argv = [
            "-fmodule-file=Compression",
            "-fmodule-file=SQLite3",
            "-fmodule-file=zlib",
        ],
    )

    _explicit_precompiled_modules_test(
        name = "{}_cross_import_overlay_dep_pollution_no_default_precompiled_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:cross_import_overlay_dep_pollution",
        expected_argv = [
            "-Xfrontend -disable-cross-import-overlay-search",
            "-Xfrontend -swift-module-cross-import -Xfrontend Testing -Xfrontend",  # Any cross module import is ok, different Xcode version have different ones
        ],
    )

    _precompiled_modules_test(
        name = "{}_cross_import_overlay_dep_pollution_default_precompiled_modules_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:cross_import_overlay_dep_pollution",
        expected_argv = [
            "-Xfrontend -disable-cross-import-overlay-search",
            "-Xfrontend -swift-module-cross-import -Xfrontend Testing -Xfrontend",  # Any cross module import is ok, different Xcode version have different ones
        ],
    )

    _explicit_precompiled_modules_test(
        name = "{}_linking_cross_import_overlay_transitioned_test".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        target_under_test = "//test/fixtures/precompiled_modules:linking_cross_import_overlay",
        expected_argv = [
            "-Xfrontend -explicit-swift-module-map-file -Xfrontend $(BIN_DIR)/test/fixtures/precompiled_modules/linking_cross_import_overlay.swift-system-explicit-module-map.json",
            "-Xfrontend -disable-cross-import-overlay-search",
            "-Xfrontend -swift-module-cross-import -Xfrontend Testing -Xfrontend",
            "Testing.framework/Modules/Testing.swiftcrossimport/AppKit.swiftoverlay",
        ],
        target_compatible_with = select({
            ":has_testing_appkit_overlay": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "//test/fixtures/precompiled_modules:application_extension_unavailable_transitioned",
            "//test/fixtures/precompiled_modules:available_testing_import_ios_12",
            "//test/fixtures/precompiled_modules:foundation_requires_explicit_dep_transitioned",
            "//test/fixtures/precompiled_modules:hello",
            "//test/fixtures/precompiled_modules:hello_with_explicit_deps_transitioned",
            "//test/fixtures/precompiled_modules:linking_cross_import_overlay_transitioned",
            "//test/fixtures/precompiled_modules:lower_version_bin_transitioned",
            "//test/fixtures/precompiled_modules:min_os_bin_transitioned",
            "//test/fixtures/precompiled_modules:objc_interop_bin_transitioned",
            "//test/fixtures/precompiled_modules:xctest_explicit_deps_with_testing_no_modulemap_transitioned",
            "//test/fixtures/precompiled_modules:xctest_explicit_deps_with_testing_transitioned",
            "//test/fixtures/precompiled_modules:xctest_with_testing_no_modulemap_transitioned",
            "//test/fixtures/precompiled_modules:xctest_with_testing_transitioned",
        ] + [
            "//test/fixtures/precompiled_modules:" + t
            for t in CROSS_PLATFORM_TARGETS
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
