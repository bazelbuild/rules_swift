"""Tests for the default precompiled-modules injection."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "unittest")
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

def _system_swiftinterface_sdk_min_os_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    matching_actions = [
        action
        for action in actions
        if action.mnemonic == "SwiftCompileModuleInterface"
    ]

    if len(matching_actions) != 1:
        unittest.fail(
            env,
            "Expected exactly one SwiftCompileModuleInterface action, but found {}. Available actions: {}".format(
                len(matching_actions),
                [action.mnemonic for action in actions],
            ),
        )
        return analysistest.end(env)

    argv = matching_actions[0].argv
    target_triple = None
    for i in range(len(argv) - 1):
        if argv[i] == "-target":
            target_triple = argv[i + 1]
            break

    if not target_triple:
        unittest.fail(
            env,
            "Expected SwiftCompileModuleInterface action to pass -target. Arguments were: {}".format(argv),
        )
        return analysistest.end(env)

    if not target_triple.endswith(ctx.attr.expected_target_suffix):
        unittest.fail(
            env,
            "Expected system Swift interface -target to use the SDK min OS, but got '{}'. Arguments were: {}".format(
                target_triple,
                argv,
            ),
        )

    return analysistest.end(env)

_system_swiftinterface_macos_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:macos_minimum_os": "14.0",
    },
)

_system_swiftinterface_ios_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:ios_minimum_os": "12.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:ios_arm64"),
        ],
    },
)

_system_swiftinterface_ios_simulator_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:ios_minimum_os": "12.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:ios_sim_arm64"),
        ],
    },
)

_system_swiftinterface_tvos_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:tvos_minimum_os": "12.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:tvos_arm64"),
        ],
    },
)

_system_swiftinterface_tvos_simulator_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:tvos_minimum_os": "12.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:tvos_sim_arm64"),
        ],
    },
)

_system_swiftinterface_watchos_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:watchos_minimum_os": "9.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:watchos_device_arm64"),
        ],
    },
)

_system_swiftinterface_watchos_simulator_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:watchos_minimum_os": "9.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:watchos_x86_64"),
        ],
    },
)

_system_swiftinterface_visionos_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:minimum_os_version": "1.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:visionos_arm64"),
        ],
    },
)

_system_swiftinterface_visionos_simulator_sdk_min_os_test = analysistest.make(
    _system_swiftinterface_sdk_min_os_test_impl,
    attrs = {
        "expected_target_suffix": attr.string(mandatory = True),
    },
    config_settings = {
        "//command_line_option:minimum_os_version": "1.0",
        "//command_line_option:platforms": [
            Label("@build_bazel_apple_support//platforms:visionos_sim_arm64"),
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
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
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
            "-Xwrapped-swift=-driver-explicit-swift-module-map-file=$(BIN_DIR)/test/fixtures/precompiled_modules/linking_cross_import_overlay.swift-system-explicit-module-map.json",
            "-Xfrontend -disable-cross-import-overlay-search",
            "-Xfrontend -swift-module-cross-import -Xfrontend Testing -Xfrontend __BAZEL_XCODE_DEVELOPER_DIR__/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework/Modules/Testing.swiftcrossimport/AppKit.swiftoverlay",
        ],
        target_compatible_with = select({
            ":has_testing_appkit_overlay": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
    )

    _system_swiftinterface_macos_sdk_min_os_test(
        name = "{}_system_swiftinterface_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-macos26.4",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_with_sdk_min_os",
    )

    _system_swiftinterface_ios_sdk_min_os_test(
        name = "{}_system_swiftinterface_ios_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-ios26.4",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_ios_with_sdk_min_os",
    )

    _system_swiftinterface_ios_simulator_sdk_min_os_test(
        name = "{}_system_swiftinterface_ios_simulator_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-ios26.4-simulator",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_ios_simulator_with_sdk_min_os",
    )

    _system_swiftinterface_tvos_sdk_min_os_test(
        name = "{}_system_swiftinterface_tvos_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-tvos26.4",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_tvos_with_sdk_min_os",
    )

    _system_swiftinterface_tvos_simulator_sdk_min_os_test(
        name = "{}_system_swiftinterface_tvos_simulator_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-tvos26.4-simulator",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_tvos_simulator_with_sdk_min_os",
    )

    _system_swiftinterface_watchos_sdk_min_os_test(
        name = "{}_system_swiftinterface_watchos_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-watchos26.4",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_watchos_with_sdk_min_os",
    )

    _system_swiftinterface_watchos_simulator_sdk_min_os_test(
        name = "{}_system_swiftinterface_watchos_simulator_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-watchos26.4-simulator",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_watchos_simulator_with_sdk_min_os",
    )

    _system_swiftinterface_visionos_sdk_min_os_test(
        name = "{}_system_swiftinterface_visionos_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-xros26.4",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_visionos_with_sdk_min_os",
    )

    _system_swiftinterface_visionos_simulator_sdk_min_os_test(
        name = "{}_system_swiftinterface_visionos_simulator_uses_sdk_min_os_test".format(name),
        expected_target_suffix = "-apple-xros26.4-simulator",
        tags = all_tags,
        target_compatible_with = select({
            "//test:apple_build_tests_enabled": [],
            "//conditions:default": ["@platforms//:incompatible"],
        }),
        target_under_test = "//test/fixtures/precompiled_modules:system_swiftinterface_visionos_simulator_with_sdk_min_os",
    )

    build_test(
        name = "{}_build_test".format(name),
        targets = [
            "//test/fixtures/precompiled_modules:application_extension_unavailable_transitioned",
            "//test/fixtures/precompiled_modules:foundation_requires_explicit_dep_transitioned",
            "//test/fixtures/precompiled_modules:hello",
            "//test/fixtures/precompiled_modules:hello_with_explicit_deps_transitioned",
            "//test/fixtures/precompiled_modules:linking_cross_import_overlay_transitioned",
            "//test/fixtures/precompiled_modules:lower_version_bin_transitioned",
            "//test/fixtures/precompiled_modules:min_os_bin_transitioned",
            "//test/fixtures/precompiled_modules:objc_interop_bin_transitioned",
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
