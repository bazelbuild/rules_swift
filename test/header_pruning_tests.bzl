"""Regression tests for explicit-module header action inputs."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//swift:swift_clang_module_aspect.bzl", "swift_clang_module_aspect")
load("//test/rules:action_inputs_test.bzl", "make_action_inputs_test_rule")

_FEATURES = [
    "swift.use_c_modules",
    "swift.emit_c_module",
    "swift.layering_check_for_c_deps",
    "-swift.add_default_precompiled_modules",
]

_pruned_test = make_action_inputs_test_rule(
    config_settings = {"//command_line_option:features": _FEATURES},
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

_unchecked_test = make_action_inputs_test_rule(
    config_settings = {"//command_line_option:features": _FEATURES + ["-swift.layering_check_for_c_deps"]},
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

_always_test = make_action_inputs_test_rule(
    config_settings = {"//command_line_option:features": _FEATURES + ["swift.headers_always_action_inputs"]},
    extra_target_under_test_aspects = [swift_clang_module_aspect],
)

def header_pruning_test_suite(name, tags = []):
    """Tests pruning and the include paths that must remain conservative.

    Args:
        name: The test suite name.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags
    for target, present, absent in [
        ("top", ["top.h", "middle.h", "middle.swift.pcm", "leaf.swift.pcm"], ["leaf.h"]),
        ("through_pure", ["empty.h", "top.swift.pcm"], ["leaf.h", "middle.h", "top.h"]),
        ("legacy_consumer", ["top.h", "middle.h", "leaf.h"], []),
        ("system", ["top.h", "middle.h", "leaf.h"], []),
        ("textual_consumer", ["top.h", "middle.h", "leaf.h"], []),
        ("excluded_consumer", ["top.h", "middle.h", "leaf.h"], []),
        ("custom_consumer", ["middle.h", "leaf.h"], []),
        ("inc_consumer", ["top.h", "middle.h", "leaf.h"], []),
        ("generated", ["generated-Swift.h", "top.h", "middle.h", "leaf.h"], []),
    ]:
        _pruned_test(
            name = name + "_" + target,
            target_under_test = "//test/fixtures/header_pruning:" + target,
            mnemonic = "SwiftPrecompileCModule",
            expected_inputs = present,
            not_expected_inputs = absent,
            tags = all_tags,
        )

    for suffix, test_rule, target, mnemonic, present, absent in [
        ("no_layering_check", _unchecked_test, "top", "SwiftPrecompileCModule", ["leaf.h"], []),
        ("always_pcm", _always_test, "top", "SwiftPrecompileCModule", ["leaf.h"], []),
        ("pure_swift", _pruned_test, "consumer", "SwiftCompile", ["top.swift.pcm", "leaf.swift.pcm"], ["top.h", "middle.h", "leaf.h"]),
    ]:
        test_rule(
            name = name + "_" + suffix,
            target_under_test = "//test/fixtures/header_pruning:" + target,
            mnemonic = mnemonic,
            expected_inputs = present,
            not_expected_inputs = absent,
            tags = all_tags,
        )

    build_test(
        name = name + "_build",
        targets = ["//test/fixtures/header_pruning:pruned_pcms"],
        tags = all_tags,
    )

    native.test_suite(name = name, tags = all_tags)
