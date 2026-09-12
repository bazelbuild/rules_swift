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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:providers.bzl", "SwiftInfo")
load(
    "//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load("//test/rules:action_inputs_test.bzl", "make_action_inputs_test_rule")
load("//test/rules:provider_test.bzl", "make_provider_test_rule")

DBG_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "-swift.cacheable_swiftmodules",
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
    "//command_line_option:features": [
        "-swift.cacheable_swiftmodules",
    ],
}

FASTBUILD_FULL_DI_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "fastbuild",
    "//command_line_option:features": [
        "-swift.cacheable_swiftmodules",
        "swift.full_debug_info",
    ],
}

OPT_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "opt",
    "//command_line_option:features": [
        "-swift.cacheable_swiftmodules",
    ],
}

CACHEABLE_OPT_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "opt",
    "//command_line_option:features": [
        "swift.cacheable_swiftmodules",
        "swift.debug_prefix_map",
    ],
}

dbg_action_command_line_test = make_action_command_line_test_rule(
    config_settings = DBG_CONFIG_SETTINGS,
)

cacheable_dbg_action_command_line_test = make_action_command_line_test_rule(
    config_settings = CACHEABLE_DBG_CONFIG_SETTINGS,
)

fastbuild_action_command_line_test = make_action_command_line_test_rule(
    config_settings = FASTBUILD_CONFIG_SETTINGS,
)

fastbuild_full_di_action_command_line_test = make_action_command_line_test_rule(
    config_settings = FASTBUILD_FULL_DI_CONFIG_SETTINGS,
)

opt_action_command_line_test = make_action_command_line_test_rule(
    config_settings = OPT_CONFIG_SETTINGS,
)

cacheable_opt_action_command_line_test = make_action_command_line_test_rule(
    config_settings = CACHEABLE_OPT_CONFIG_SETTINGS,
)

xcode_remap_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "dbg",
        "//command_line_option:features": [
            "swift.debug_prefix_map",
            "swift.remap_xcode_path",
        ],
    },
)

unsupported_developer_dir_xcode_remap_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "dbg",
        "//command_line_option:features": [
            "-swift._supports_developer_dir",
            "swift.debug_prefix_map",
            "swift.remap_xcode_path",
        ],
    },
)

def _debug_module_linking_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)
    if ctx.attr.is_binary:
        # swift_binary intentionally hides its module from SwiftInfo so that
        # dependents cannot import it. Find the declared compilation output.
        swiftmodules = [
            output
            for action in actions
            if action.mnemonic in ["SwiftCompile", "SwiftDeriveFiles"]
            for output in action.outputs.to_list()
            if output.extension == "swiftmodule"
        ]
    else:
        swiftmodules = [
            module.swift.swiftmodule
            for module in target[SwiftInfo].direct_modules
            if module.swift and module.swift.swiftmodule
        ]
    asserts.equals(env, 1, len(swiftmodules), "Expected exactly one Swift module")
    if len(swiftmodules) != 1:
        return analysistest.end(env)
    swiftmodule = swiftmodules[0]

    # Check the actual linker inputs propagated by the library. Darwin uses
    # -add_ast_path; other platforms propagate a SwiftModuleWrap output.
    if ctx.attr.is_binary:
        link_actions = [a for a in actions if a.mnemonic == "CppLink"]
        asserts.equals(env, 1, len(link_actions), "Expected exactly one CppLink action")
        if len(link_actions) != 1:
            return analysistest.end(env)
        link_flags = link_actions[0].argv
        additional_inputs = link_actions[0].inputs.to_list()
    else:
        linker_inputs = target[CcInfo].linking_context.linker_inputs.to_list()
        link_flags = [flag for inputs in linker_inputs for flag in inputs.user_link_flags]
        additional_inputs = [file for inputs in linker_inputs for file in inputs.additional_inputs]
    modulewrap_actions = [a for a in actions if a.mnemonic == "SwiftModuleWrap"]
    ast_flag = "-Wl,-add_ast_path,{}".format(swiftmodule.path)
    if ctx.attr.expect_embedding:
        if modulewrap_actions:
            asserts.equals(env, 1, len(modulewrap_actions))
            wrapped_modules = modulewrap_actions[0].outputs.to_list()
            asserts.equals(env, 1, len(wrapped_modules), "Expected exactly one wrapped module")
            if len(wrapped_modules) != 1:
                return analysistest.end(env)
            wrapped_module = wrapped_modules[0]
            asserts.true(env, wrapped_module.path in link_flags)
            asserts.true(env, wrapped_module in additional_inputs)
        else:
            asserts.true(env, ast_flag in link_flags)
            asserts.true(env, swiftmodule in additional_inputs)
    else:
        asserts.equals(env, [], modulewrap_actions)
        asserts.false(env, ast_flag in link_flags)
        asserts.equals(env, ctx.attr.expect_module_input, swiftmodule in additional_inputs)

    return analysistest.end(env)

_EXPLICIT_DEBUG_MODULE_PATH_FEATURES = [
    "swift.debug_module_path",
    "swift.emit_c_module",
    "swift.use_c_modules",
    "swift.use_explicit_swift_module_map",
    "-swift.no_embed_debug_module",
]

debug_module_outputs_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "dbg",
        "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES + [
            "swift.split_derived_files_generation",
        ],
    },
)

legacy_debug_module_outputs_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "dbg",
        "//command_line_option:features": [
            "-swift.debug_module_path",
            "swift.emit_c_module",
            "swift.use_c_modules",
            "swift.use_explicit_swift_module_map",
        ],
    },
)

opt_debug_module_outputs_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
        "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES,
    },
)

fastbuild_debug_module_outputs_test = make_provider_test_rule(
    config_settings = {
        "//command_line_option:compilation_mode": "fastbuild",
        "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES,
    },
)

DEBUG_MODULE_PATH_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES,
}

debug_module_path_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_CONFIG_SETTINGS,
)

debug_module_path_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = DEBUG_MODULE_PATH_CONFIG_SETTINGS,
)

DEBUG_MODULE_PATH_DISABLED_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "-swift.debug_module_path",
        "swift.emit_c_module",
        "swift.use_c_modules",
        "swift.use_explicit_swift_module_map",
        "-swift.no_embed_debug_module",
    ],
}

debug_module_path_disabled_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_DISABLED_CONFIG_SETTINGS,
)

debug_module_path_disabled_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = DEBUG_MODULE_PATH_DISABLED_CONFIG_SETTINGS,
)

DEBUG_MODULE_PATH_SWIFT_MAP_ONLY_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "swift.debug_module_path",
        "-swift.use_c_modules",
        "swift.use_explicit_swift_module_map",
        "-swift.no_embed_debug_module",
    ],
}

debug_module_path_swift_map_only_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_SWIFT_MAP_ONLY_CONFIG_SETTINGS,
)

debug_module_path_swift_map_only_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = DEBUG_MODULE_PATH_SWIFT_MAP_ONLY_CONFIG_SETTINGS,
)

DEBUG_MODULE_PATH_C_MODULES_ONLY_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "swift.debug_module_path",
        "swift.emit_c_module",
        "swift.use_c_modules",
        "-swift.use_explicit_swift_module_map",
        "-swift.no_embed_debug_module",
    ],
}

debug_module_path_c_modules_only_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_C_MODULES_ONLY_CONFIG_SETTINGS,
)

debug_module_path_c_modules_only_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = DEBUG_MODULE_PATH_C_MODULES_ONLY_CONFIG_SETTINGS,
)

DEBUG_MODULE_PATH_SPLIT_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES + ["swift.split_derived_files_generation"],
}

debug_module_path_split_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_SPLIT_CONFIG_SETTINGS,
)

debug_module_path_split_inputs_test = make_action_inputs_test_rule(
    config_settings = DEBUG_MODULE_PATH_SPLIT_CONFIG_SETTINGS,
)

debug_module_path_split_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = DEBUG_MODULE_PATH_SPLIT_CONFIG_SETTINGS,
)

DEBUG_MODULE_PATH_FASTBUILD_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "fastbuild",
    "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES,
}

debug_module_path_fastbuild_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_FASTBUILD_CONFIG_SETTINGS,
)

DEBUG_MODULE_PATH_OPT_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "opt",
    "//command_line_option:features": _EXPLICIT_DEBUG_MODULE_PATH_FEATURES,
}

debug_module_path_opt_test = make_action_command_line_test_rule(
    config_settings = DEBUG_MODULE_PATH_OPT_CONFIG_SETTINGS,
)

debug_module_path_opt_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = DEBUG_MODULE_PATH_OPT_CONFIG_SETTINGS,
)

NO_EMBED_DEBUG_MODULE_CONFIG_SETTINGS = {
    "//command_line_option:compilation_mode": "dbg",
    "//command_line_option:features": [
        "-swift.debug_module_path",
        "-swift.use_c_modules",
        "-swift.use_explicit_swift_module_map",
        "swift.no_embed_debug_module",
    ],
}

no_embed_debug_module_linking_test = analysistest.make(
    _debug_module_linking_test_impl,
    attrs = {
        "expect_module_input": attr.bool(default = False),
        "expect_embedding": attr.bool(default = True),
        "is_binary": attr.bool(default = False),
    },
    config_settings = NO_EMBED_DEBUG_MODULE_CONFIG_SETTINGS,
)

def debug_settings_test_suite(name, tags = []):
    """Test suite for serializing debugging options.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that default outputs include the modules needed for debugging.
    debug_module_outputs_test(
        name = "{}_debug_module_outputs_dependency_dbg".format(name),
        expected_files = [
            "test_fixtures_debug_settings_module_path_binary.swiftmodule",
            "test_fixtures_debug_settings_simple.swiftmodule",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

    fastbuild_debug_module_outputs_test(
        name = "{}_debug_module_outputs_dependency_fastbuild".format(name),
        expected_files = [
            "test_fixtures_debug_settings_module_path_binary.swiftmodule",
            "test_fixtures_debug_settings_simple.swiftmodule",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

    debug_module_outputs_test(
        name = "{}_debug_module_outputs_private_dependencies_dbg".format(name),
        expected_files = [
            "test_fixtures_private_deps_client_swift_deps.swiftmodule",
            "test_fixtures_private_deps_private_swift.swiftmodule",
            "test_fixtures_private_deps_public_swift.swiftmodule",
            "private_cc.swift.pcm",
            "public_cc.swift.pcm",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/debug_settings:private_deps_binary",
    )

    opt_debug_module_outputs_test(
        name = "{}_debug_module_outputs_private_dependencies_opt".format(name),
        expected_files = [
            "-test_fixtures_private_deps_client_swift_deps.swiftmodule",
            "-test_fixtures_private_deps_private_swift.swiftmodule",
            "-test_fixtures_private_deps_public_swift.swiftmodule",
            "-private_cc.swift.pcm",
            "-public_cc.swift.pcm",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/debug_settings:private_deps_binary",
    )

    debug_module_outputs_test(
        name = "{}_debug_module_outputs_swift_test_dbg".format(name),
        expected_files = [
            "test_fixtures_precompiled_modules_simple_xctest.swiftmodule",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/precompiled_modules:simple_xctest",
    )

    opt_debug_module_outputs_test(
        name = "{}_debug_module_outputs_swift_test_opt".format(name),
        expected_files = [
            "-test_fixtures_precompiled_modules_simple_xctest.swiftmodule",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/precompiled_modules:simple_xctest",
    )

    legacy_debug_module_outputs_test(
        name = "{}_legacy_debug_module_outputs".format(name),
        expected_files = [
            "-test_fixtures_debug_settings_module_path_binary.swiftmodule",
            "-test_fixtures_debug_settings_simple.swiftmodule",
            "*",
        ],
        field = "files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

    # Record the module path and make the module available without embedding it.
    debug_module_path_test(
        name = "{}_debug_module_path_explicit_modules".format(name),
        expected_argv = [
            "-debug-module-path $(BIN_DIR)/test/fixtures/debug_settings/test_fixtures_debug_settings_simple.swiftmodule",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_linking_test(
        name = "{}_debug_module_path_explicit_modules_linking".format(name),
        expect_module_input = True,
        expect_embedding = False,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_fastbuild_test(
        name = "{}_debug_module_path_fastbuild".format(name),
        expected_argv = [
            "-debug-module-path $(BIN_DIR)/test/fixtures/debug_settings/test_fixtures_debug_settings_simple.swiftmodule",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    # Optimized builds do not request debug module tracking or linker inputs.
    debug_module_path_opt_test(
        name = "{}_debug_module_path_opt".format(name),
        not_expected_argv = [
            "-debug-module-path",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_opt_linking_test(
        name = "{}_debug_module_path_opt_binary_linking".format(name),
        expect_module_input = False,
        expect_embedding = False,
        is_binary = True,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:binary",
    )

    # Disabling the feature or either explicit-module requirement retains
    # legacy embedding.
    debug_module_path_disabled_test(
        name = "{}_debug_module_path_disabled".format(name),
        not_expected_argv = [
            "-debug-module-path",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_disabled_linking_test(
        name = "{}_debug_module_path_disabled_linking".format(name),
        expect_embedding = True,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_swift_map_only_test(
        name = "{}_debug_module_path_swift_map_only".format(name),
        not_expected_argv = [
            "-debug-module-path",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_swift_map_only_linking_test(
        name = "{}_debug_module_path_swift_map_only_linking".format(name),
        expect_embedding = True,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_c_modules_only_test(
        name = "{}_debug_module_path_c_modules_only".format(name),
        not_expected_argv = [
            "-debug-module-path",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    debug_module_path_c_modules_only_linking_test(
        name = "{}_debug_module_path_c_modules_only_linking".format(name),
        expect_embedding = True,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    no_embed_debug_module_linking_test(
        name = "{}_no_embed_debug_module_linking".format(name),
        expect_module_input = False,
        expect_embedding = False,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    # Split compilation records the path only in the object action, without
    # making the module an input to its own compilation.
    debug_module_path_split_test(
        name = "{}_debug_module_path_dependency".format(name),
        expected_argv = [
            "-debug-module-path $(BIN_DIR)/test/fixtures/debug_settings/test_fixtures_debug_settings_module_path_binary.swiftmodule",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

    debug_module_path_split_inputs_test(
        name = "{}_debug_module_path_dependency_inputs".format(name),
        not_expected_inputs = [
            "test/fixtures/debug_settings/test_fixtures_debug_settings_module_path_binary.swiftmodule",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

    debug_module_path_split_test(
        name = "{}_debug_module_path_dependency_derive_files".format(name),
        not_expected_argv = [
            "-debug-module-path",
        ],
        mnemonic = "SwiftDeriveFiles",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

    debug_module_path_split_linking_test(
        name = "{}_debug_module_path_dependency_linking".format(name),
        expect_module_input = True,
        expect_embedding = False,
        is_binary = True,
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:module_path_binary",
    )

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
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
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
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
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
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
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
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    # Verify that `-c opt` builds do not serialize debugging options, but have
    # appropriate flags otherwise.
    opt_action_command_line_test(
        name = "{}_opt_build".format(name),
        expected_argv = [
            "-DNDEBUG",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        not_expected_argv = [
            "-DDEBUG",
            "-Xfrontend -serialize-debugging-options",
            "-Xwrapped-swift=-debug-prefix-pwd-is-dot",
            "-g",
            "-gline-tables-only",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    # Verify that `-c opt` builds do not serialize debugging options, but have
    # appropriate flags otherwise.
    cacheable_opt_action_command_line_test(
        name = "{}_cacheable_opt_build".format(name),
        expected_argv = [
            "-DNDEBUG",
            "-Xfrontend -no-serialize-debugging-options",
            "-Xwrapped-swift=-file-prefix-pwd-is-dot",
        ],
        not_expected_argv = [
            "-Xfrontend -serialize-debugging-options",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    xcode_remap_command_line_test(
        name = "{}_remap_xcode_path".format(name),
        expected_argv = [
            "-debug-prefix-map",
            "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR",
        ],
        target_compatible_with = ["@platforms//os:macos"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    unsupported_developer_dir_xcode_remap_command_line_test(
        name = "{}_remap_xcode_path_unsupported_developer_dir".format(name),
        not_expected_argv = [
            "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR",
        ],
        target_compatible_with = ["@platforms//os:macos"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/debug_settings:simple",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
