# Copyright 2026 The Bazel Authors. All rights reserved.
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

"""Tests for `swift_overlay` and `swift_clang_module_aspect` overlay support."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "@build_bazel_rules_swift//swift:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)
load(
    "@build_bazel_rules_swift//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
)
load(
    "@build_bazel_rules_swift//test/rules:provider_test.bzl",
    "provider_test",
)

visibility("private")

_COMMON_FEATURES = [
    "-swift.emit_swiftinterface",
]

_EXPLICIT_MODULES_FEATURES = _COMMON_FEATURES + [
    "swift.emit_c_module",
    "swift.use_c_modules",
    "-swift.compile_in_parallel",
]

_IMPLICIT_MODULES_FEATURES = _COMMON_FEATURES + [
    "-swift.use_c_modules",
    "-swift.compile_in_parallel",
]

_PARALLEL_COMPILE_FEATURES = _COMMON_FEATURES + [
    "swift.emit_c_module",
    "swift.use_c_modules",
    "swift.compile_in_parallel",
]

_WMO_FEATURES = _COMMON_FEATURES + [
    "swift.emit_c_module",
    "swift.use_c_modules",
    "swift.opt",
    "swift.opt_uses_wmo",
    "-swift.compile_in_parallel",
]

explicit_modules_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _EXPLICIT_MODULES_FEATURES,
    },
)

explicit_modules_aspect_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _EXPLICIT_MODULES_FEATURES,
    },
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

implicit_modules_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _IMPLICIT_MODULES_FEATURES,
    },
)

implicit_modules_aspect_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _IMPLICIT_MODULES_FEATURES,
    },
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

parallel_compile_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _PARALLEL_COMPILE_FEATURES,
    },
)

parallel_compile_aspect_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _PARALLEL_COMPILE_FEATURES,
    },
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

wmo_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _WMO_FEATURES,
    },
)

wmo_aspect_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": _WMO_FEATURES,
    },
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

COMPILATION_MODES = {
    "explicit_modules": struct(
        action_command_line_test = explicit_modules_action_command_line_test,
        aspect_action_command_line_test = explicit_modules_aspect_action_command_line_test,
        mnemonic = "SwiftCompile",
    ),
    "implicit_modules": struct(
        action_command_line_test = implicit_modules_action_command_line_test,
        aspect_action_command_line_test = implicit_modules_aspect_action_command_line_test,
        mnemonic = "SwiftCompile",
    ),
    "parallel_compile": struct(
        action_command_line_test = parallel_compile_action_command_line_test,
        aspect_action_command_line_test = parallel_compile_aspect_action_command_line_test,
        mnemonic = "SwiftCompileModule",
    ),
    "wmo": struct(
        action_command_line_test = wmo_action_command_line_test,
        aspect_action_command_line_test = wmo_aspect_action_command_line_test,
        mnemonic = "SwiftCompile",
    ),
}

def overlay_test_suite(name, tags = []):
    """Test suite for `swift_overlay` and `swift_clang_module_aspect`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    for mode_name, mode in COMPILATION_MODES.items():
        expected_overlay_inputs = [
            "test/fixtures/overlay/cc_with_overlay.swift.modulemap",
            "test_fixtures_overlay_public_dep.swiftmodule",
            "test_fixtures_overlay_private_dep.swiftmodule",
            "*",
        ]
        if mode_name == "implicit_modules":
            expected_overlay_inputs.append(
                "-test/fixtures/overlay/cc_with_overlay.swift.pcm",
            )
        else:
            expected_overlay_inputs.append(
                "test/fixtures/overlay/cc_with_overlay.swift.pcm",
            )

        # Verify that the overlay compile action registered on the `cc_library`
        # by `swift_clang_module_aspect` uses the underlying C target's module
        # name, passes `-parse-as-library`, and receives the underlying C module
        # (modulemap and, for explicit modules, pcm) along with both public and
        # private dependencies of the `swift_overlay`.
        mode.aspect_action_command_line_test(
            name = "{}_{}_overlay_compile".format(name, mode_name),
            expected_argv = [
                "-module-name",
                "test_fixtures_overlay_cc_with_overlay",
                "-parse-as-library",
            ],
            expected_inputs = expected_overlay_inputs,
            mnemonic = mode.mnemonic,
            tags = all_tags,
            target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_overlay",
        )

        # Verify that a downstream `swift_library` depending on a `cc_library`
        # with a `swift_overlay` receives the overlay's `.swiftmodule` and its
        # public `deps` `.swiftmodule`, but not the overlay's `private_deps`
        # `.swiftmodule`.
        mode.action_command_line_test(
            name = "{}_{}_downstream_compile_inputs".format(name, mode_name),
            expected_inputs = [
                "test_fixtures_overlay_cc_with_overlay.swiftmodule",
                "test_fixtures_overlay_public_dep.swiftmodule",
                "-test_fixtures_overlay_private_dep.swiftmodule",
                "*",
            ],
            mnemonic = mode.mnemonic,
            tags = all_tags,
            target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:downstream_of_overlay",
        )

        # Verify that when a `cc_library` combines `swift_interop_hint` (setting
        # a custom `module_name`) with `swift_overlay`, the overlay compile
        # action compiles the Swift overlay module under that custom module name.
        mode.aspect_action_command_line_test(
            name = "{}_{}_custom_module_name_overlay_compile".format(name, mode_name),
            expected_argv = [
                "-module-name CustomOverlayMod",
                "-parse-as-library",
            ],
            mnemonic = mode.mnemonic,
            tags = all_tags,
            target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_custom_module_and_overlay",
        )

    # Verify that the `SwiftInfo` produced by `swift_clang_module_aspect` on a
    # `cc_library` with a `swift_overlay` contains both the Clang `module_map`
    # and the compiled `swiftmodule` in its `direct_modules`, and propagates the
    # overlay's public `deps` but not its `private_deps` in `transitive_modules`.
    provider_test(
        name = "{}_swift_info_clang_module_map".format(name),
        expected_files = [
            "test/fixtures/overlay/cc_with_overlay.swift.modulemap",
        ],
        field = "direct_modules.clang!.module_map!",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_overlay_swift_info",
    )

    provider_test(
        name = "{}_swift_info_swiftmodule".format(name),
        expected_files = [
            "test_fixtures_overlay_cc_with_overlay.swiftmodule",
        ],
        field = "direct_modules.swift!.swiftmodule",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_overlay_swift_info",
    )

    provider_test(
        name = "{}_swift_info_transitive_swiftmodules".format(name),
        expected_files = [
            "test_fixtures_overlay_cc_with_overlay.swiftmodule",
            "test_fixtures_overlay_public_dep.swiftmodule",
            "-test_fixtures_overlay_private_dep.swiftmodule",
            "*",
        ],
        field = "transitive_modules.swift!.swiftmodule",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_overlay_swift_info",
    )

    # Verify that a downstream `swift_library` depending on a `cc_library` with
    # a `swift_overlay` propagates the static libraries of the overlay and both
    # its public `deps` and `private_deps` in its `CcInfo.linking_context`.
    provider_test(
        name = "{}_downstream_linking_context_libraries".format(name),
        expected_files = [
            "test/fixtures/overlay/liboverlay.lo",
            "test/fixtures/overlay/libpublic_dep.a",
            "test/fixtures/overlay/libprivate_dep.a",
            "*",
        ],
        field = select({
            "@build_bazel_apple_support//constraints:apple": (
                "linking_context.linker_inputs.libraries.static_library!"
            ),
            "//conditions:default": (
                "linking_context.linker_inputs.libraries.pic_static_library!"
            ),
        }),
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:downstream_of_overlay",
    )

    # Verify that when a `cc_library` uses both `swift_interop_hint(module_name)`
    # and `swift_overlay`, the `SwiftInfo` produced by `swift_clang_module_aspect`
    # uses the custom module name and produces a matching `.swiftmodule`.
    provider_test(
        name = "{}_custom_module_name_swift_info_name".format(name),
        expected_values = [
            "CustomOverlayMod",
        ],
        field = "direct_modules.name",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_custom_module_and_overlay_swift_info",
    )

    provider_test(
        name = "{}_custom_module_name_swift_info_swiftmodule".format(name),
        expected_files = [
            "test/fixtures/overlay/CustomOverlayMod.swiftmodule",
        ],
        field = "direct_modules.swift!.swiftmodule",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_custom_module_and_overlay_swift_info",
    )

    # Verify that attaching a `swift_overlay` from a different BUILD package
    # fails analysis.
    analysis_failure_test(
        name = "{}_cross_package_overlay_fails".format(name),
        expected_message = "is not in the same BUILD package as the target",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:invalid_cross_pkg_swift",
    )

    # Verify that attaching multiple `swift_overlay` targets to a single target
    # fails analysis.
    analysis_failure_test(
        name = "{}_multiple_overlays_fails".format(name),
        expected_message = "Conflicting Swift overlay info from aspect hints",
        tags = all_tags,
        target_under_test = "@build_bazel_rules_swift//test/fixtures/overlay:invalid_multiple_overlays_swift",
    )

    # Verify that targets with `swift_overlay` build end-to-end.
    build_test(
        name = "{}_build_test".format(name),
        tags = all_tags,
        targets = [
            "@build_bazel_rules_swift//test/fixtures/overlay:cc_with_custom_module_and_overlay_swift_info",
            "@build_bazel_rules_swift//test/fixtures/overlay:downstream_of_overlay",
        ],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
