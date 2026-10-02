# Copyright 2020 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Tests for debugging-related command line flags under various configs."""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

visibility("private")

DBG_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
}

DBG_EMBED_MODULE_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "-swift.no_embed_debug_module",
    ],
}

DBG_NO_EMBED_MODULE_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "swift.no_embed_debug_module",
    ],
}

CACHEABLE_DBG_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "swift.cacheable_swiftmodules",
    ],
}

FASTBUILD_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "fastbuild",
}

FASTBUILD_EMBED_MODULE_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "fastbuild",
    "//command_line_option:features": [
        "-swift.no_embed_debug_module",
    ],
}

FASTBUILD_FULL_DI_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "fastbuild",
    "//command_line_option:features": [
        "swift.full_debug_info",
    ],
}

OPT_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "opt",
}

OPT_EMBED_MODULE_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "opt",
    "//command_line_option:features": [
        "-swift.no_embed_debug_module",
    ],
}

dbg_action_command_line_test = make_action_command_line_test_rule(
    config_settings = DBG_CONFIG_SETTINGS,
)

dbg_embed_module_action_command_line_test = make_action_command_line_test_rule(
    config_settings = DBG_EMBED_MODULE_CONFIG_SETTINGS,
)

dbg_no_embed_module_action_command_line_test = make_action_command_line_test_rule(
    config_settings = DBG_NO_EMBED_MODULE_CONFIG_SETTINGS,
)

dbg_provider_test = make_provider_test_rule(
    config_settings = DBG_CONFIG_SETTINGS,
)

dbg_embed_module_provider_test = make_provider_test_rule(
    config_settings = DBG_EMBED_MODULE_CONFIG_SETTINGS,
)

dbg_no_embed_module_provider_test = make_provider_test_rule(
    config_settings = DBG_NO_EMBED_MODULE_CONFIG_SETTINGS,
)

cacheable_dbg_action_command_line_test = make_action_command_line_test_rule(
    config_settings = CACHEABLE_DBG_CONFIG_SETTINGS,
)

fastbuild_action_command_line_test = make_action_command_line_test_rule(
    config_settings = FASTBUILD_CONFIG_SETTINGS,
)

fastbuild_embed_module_action_command_line_test = make_action_command_line_test_rule(
    config_settings = FASTBUILD_EMBED_MODULE_CONFIG_SETTINGS,
)

fastbuild_embed_module_provider_test = make_provider_test_rule(
    config_settings = FASTBUILD_EMBED_MODULE_CONFIG_SETTINGS,
)

fastbuild_full_di_action_command_line_test = make_action_command_line_test_rule(
    config_settings = FASTBUILD_FULL_DI_CONFIG_SETTINGS,
)

opt_action_command_line_test = make_action_command_line_test_rule(
    config_settings = OPT_CONFIG_SETTINGS,
)

opt_embed_module_action_command_line_test = make_action_command_line_test_rule(
    config_settings = OPT_EMBED_MODULE_CONFIG_SETTINGS,
)

opt_embed_module_provider_test = make_provider_test_rule(
    config_settings = OPT_EMBED_MODULE_CONFIG_SETTINGS,
)

def debug_settings_test_suite(name, tags = []):
    """Test suite for serializing debugging options.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that `-c dbg` builds serialize debugging options, remap paths, and
    # have other appropriate debug flags.
    dbg_action_command_line_test(
        name = "{}_dbg_build".format(name),
        expected_argv = [
            "-DDEBUG",
            "-Xfrontend -serialize-debugging-options",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-g",
        ],
        not_expected_argv = [
            "-DNDEBUG",
            "-Xfrontend -no-serialize-debugging-options",
            "-gline-tables-only",
            "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # Verify that `-c dbg` builds with `swift.cacheable_modules` do NOT
    # serialize debugging options, but are otherwise the same as regular `dbg`
    # builds.
    cacheable_dbg_action_command_line_test(
        name = "{}_cacheable_dbg_build".format(name),
        expected_argv = [
            "-DDEBUG",
            "-Xfrontend -no-serialize-debugging-options",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-g",
        ],
        not_expected_argv = [
            "-DNDEBUG",
            "-Xfrontend -serialize-debugging-options",
            "-gline-tables-only",
            "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # Verify that `-c fastbuild` builds serialize debugging options, remap
    # paths, and have other appropriate debug flags.
    fastbuild_action_command_line_test(
        name = "{}_fastbuild_build".format(name),
        expected_argv = [
            "-DDEBUG",
            "-Xfrontend -serialize-debugging-options",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-gline-tables-only",
        ],
        not_expected_argv = [
            "-DNDEBUG",
            "-Xfrontend -no-serialize-debugging-options",
            "-g",
            "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # Verify that `-c fastbuild` builds with `swift.full_debug_info` use `-g`
    # instead of `-gline-tables-only` (this is required for Apple dSYM support).
    fastbuild_full_di_action_command_line_test(
        name = "{}_fastbuild_full_di_build".format(name),
        expected_argv = [
            "-DDEBUG",
            "-Xfrontend -serialize-debugging-options",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
            "-g",
        ],
        not_expected_argv = [
            "-DNDEBUG",
            "-Xfrontend -no-serialize-debugging-options",
            "-gline-tables-only",
            "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # Verify that `-c opt` builds do not serialize debugging options, but have
    # appropriate flags otherwise.
    opt_action_command_line_test(
        name = "{}_opt_build".format(name),
        expected_argv = [
            "-DNDEBUG",
            "-Xfrontend -no-serialize-debugging-options",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        not_expected_argv = [
            "-DDEBUG",
            "-Xfrontend -serialize-debugging-options",
            "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
            "-g",
            "-gline-tables-only",
        ],
        mnemonic = "SwiftCompileModule",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    # -------------------------------------------------------------------------
    # Debug module embedding tests
    # -------------------------------------------------------------------------

    # Verify default platform behavior in `dbg` mode: Apple toolchains embed
    # `.swiftmodule` by default, while Linux enables `swift.no_embed_debug_module`
    # by default.
    dbg_provider_test(
        name = "{}_dbg_default_embed_module_cc_info".format(name),
        expected_values = select({
            "@build_bazel_apple_support//constraints:apple": [
                "swiftmodule",
            ],
            "//conditions:default": [
                "-swiftmodule",
            ],
        }),
        field = "linking_context.linker_inputs.additional_inputs.extension",
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    dbg_action_command_line_test(
        name = "{}_dbg_default_embed_module_link".format(name),
        expected_inputs = select({
            "@build_bazel_apple_support//constraints:apple": [
                "simple.swiftmodule",
                "*",
            ],
            "//conditions:default": [
                "-simple.swiftmodule",
                "*",
            ],
        }),
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:binary",
    )

    # Verify that in `dbg` mode with `-swift.no_embed_debug_module`, the
    # `.swiftmodule` is embedded in the linking context and passed to the linker.
    dbg_embed_module_provider_test(
        name = "{}_dbg_embed_module_cc_info".format(name),
        expected_values = [
            "swiftmodule",
        ],
        field = "linking_context.linker_inputs.additional_inputs.extension",
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    dbg_embed_module_action_command_line_test(
        name = "{}_dbg_embed_module_link".format(name),
        expected_inputs = [
            "simple.swiftmodule",
            "*",
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:binary",
    )

    # Verify that in `fastbuild` mode with `-swift.no_embed_debug_module`, the
    # `.swiftmodule` is also embedded in the linking context and passed to the
    # linker.
    fastbuild_embed_module_provider_test(
        name = "{}_fastbuild_embed_module_cc_info".format(name),
        expected_values = [
            "swiftmodule",
        ],
        field = "linking_context.linker_inputs.additional_inputs.extension",
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    fastbuild_embed_module_action_command_line_test(
        name = "{}_fastbuild_embed_module_link".format(name),
        expected_inputs = [
            "simple.swiftmodule",
            "*",
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:binary",
    )

    # Verify that in `opt` mode (even with `-swift.no_embed_debug_module`), the
    # `.swiftmodule` is NOT embedded in the linking context or link inputs.
    opt_embed_module_provider_test(
        name = "{}_opt_does_not_embed_module_cc_info".format(name),
        expected_values = [
            "-swiftmodule",
        ],
        field = "linking_context.linker_inputs.additional_inputs.extension",
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    opt_embed_module_action_command_line_test(
        name = "{}_opt_does_not_embed_module_link".format(name),
        expected_inputs = [
            "-simple.swiftmodule",
            "*",
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:binary",
    )

    # Verify that enabling `swift.no_embed_debug_module` in `dbg` mode suppresses
    # `.swiftmodule` embedding on all platforms.
    dbg_no_embed_module_provider_test(
        name = "{}_dbg_no_embed_module_cc_info".format(name),
        expected_values = [
            "-swiftmodule",
        ],
        field = "linking_context.linker_inputs.additional_inputs.extension",
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:simple",
    )

    dbg_no_embed_module_action_command_line_test(
        name = "{}_dbg_no_embed_module_link".format(name),
        expected_inputs = [
            "-simple.swiftmodule",
            "*",
        ],
        mnemonic = "CppLink",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/debug_settings:binary",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
