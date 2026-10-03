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

_implicit_test = make_action_inputs_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "-swift.use_c_modules",
            "-swift.emit_c_module",
        ],
    },
)

def header_pruning_test_suite(name, tags = []):
    """Tests pruning and the include paths that must remain conservative.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Only the Xcode toolchain registers SwiftPrecompileCModule actions.
    pcm_compatible_with = select({
        "@apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    })

    # Keep direct dependency headers, but prune headers embedded in their PCMs.
    _pruned_test(
        name = "{}_top".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "middle.swift.pcm",
            "leaf.swift.pcm",
        ],
        mnemonic = "SwiftPrecompileCModule",
        not_expected_inputs = ["leaf.h"],
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:top",
    )

    # Pure Swift modules must not carry transitive headers into a consumer PCM.
    _pruned_test(
        name = "{}_through_pure".format(name),
        expected_inputs = [
            "empty.h",
            "top.swift.pcm",
        ],
        mnemonic = "SwiftPrecompileCModule",
        not_expected_inputs = [
            "leaf.h",
            "middle.h",
            "top.h",
        ],
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:through_pure",
    )

    # Callers that omit header metadata retain all headers in their own PCM action.
    _pruned_test(
        name = "{}_legacy".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:legacy",
    )

    # Callers that omit header metadata must retain headers for their consumers.
    _pruned_test(
        name = "{}_legacy_consumer".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:legacy_consumer",
    )

    # System modules retain all transitive headers.
    _pruned_test(
        name = "{}_system".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:system",
    )

    # Direct textual dependencies retain the headers their includes can reach.
    _pruned_test(
        name = "{}_textual_consumer".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:textual_consumer",
    )

    # A module with excluded headers retains their transitive include closure.
    _pruned_test(
        name = "{}_excluded".format(name),
        expected_inputs = [
            "excluded_extra.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:excluded",
    )

    # Excluded headers can include transitive headers without layering checks.
    _pruned_test(
        name = "{}_excluded_consumer".format(name),
        expected_inputs = [
            "excluded_extra.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:excluded_consumer",
    )

    # A custom module map conservatively retains all transitive headers.
    _pruned_test(
        name = "{}_custom".format(name),
        expected_inputs = [
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:custom",
    )

    # Consumers of custom module maps also retain their include closures.
    _pruned_test(
        name = "{}_custom_consumer".format(name),
        expected_inputs = [
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:custom_consumer",
    )

    # Umbrella directory headers retain the transitive headers they can include.
    _pruned_test(
        name = "{}_umbrella_consumer".format(name),
        expected_inputs = [
            "member.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:umbrella_consumer",
    )

    # cc_inc_library public headers are textual in the generated module map.
    _pruned_test(
        name = "{}_inc_consumer".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:inc_consumer",
    )

    # Precompiling a Swift-generated header retains all transitive headers.
    _pruned_test(
        name = "{}_generated".format(name),
        expected_inputs = [
            "generated-Swift.h",
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:generated",
    )

    # Header pruning requires C dependency layering checks.
    _unchecked_test(
        name = "{}_no_layering_check".format(name),
        expected_inputs = ["leaf.h"],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:top",
    )

    # The headers_always_action_inputs feature disables PCM header pruning.
    _always_test(
        name = "{}_always_pcm".format(name),
        expected_inputs = ["leaf.h"],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:top",
    )

    # Swift compilation uses PCMs without headers carried through pure Swift deps.
    _pruned_test(
        name = "{}_pure_swift".format(name),
        expected_inputs = [
            "top.swift.pcm",
            "leaf.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        not_expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:consumer",
    )

    # The headers_always_action_inputs feature retains headers in Swift actions.
    _always_test(
        name = "{}_always_swift".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
        target_under_test = "//test/fixtures/header_pruning:consumer",
    )

    # Implicit module compilation still needs headers carried by pure Swift deps.
    _implicit_test(
        name = "{}_implicit_swift".format(name),
        expected_inputs = [
            "top.h",
            "middle.h",
            "leaf.h",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//test/fixtures/header_pruning:consumer",
    )

    # Mixed-language modules preserve unchecked include headers for consumers.
    _pruned_test(
        name = "{}_mixed_consumer".format(name),
        expected_inputs = [
            "middle.h",
            "leaf.h",
            "mixed.swift.pcm",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/header_pruning:mixed_consumer",
    )

    # Build the PCMs to verify that the retained inputs are sufficient.
    build_test(
        name = "{}_build".format(name),
        targets = ["//test/fixtures/header_pruning:pruned_pcms"],
        tags = all_tags,
        target_compatible_with = pcm_compatible_with,
    )

    build_test(
        name = "{}_mixed_build".format(name),
        targets = ["//test/fixtures/header_pruning:mixed_pruned_pcm"],
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
