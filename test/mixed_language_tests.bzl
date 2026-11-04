"""Tests for mixed_language_library and first-class mixed Swift libraries."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//swift:providers.bzl", "SwiftInfo")
load("//test/rules:action_command_line_test.bzl", "make_action_command_line_test_rule")
load("//test/rules:action_inputs_test.bzl", "make_action_inputs_test_rule")
load("//test/rules:provider_test.bzl", "make_provider_test_rule", "provider_test")

_explicit_config = {
    "//command_line_option:features": [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
    ],
}

_implicit_config = {
    "//command_line_option:features": [
        "-swift.use_c_modules",
        "-swift.emit_c_module",
    ],
}

_explicit_json_config = {
    "//command_line_option:features": _explicit_config["//command_line_option:features"] + [
        "swift.use_explicit_swift_module_map",
    ],
}

_explicit_without_pcm_config = dict(_explicit_config, **{
    "//command_line_option:extra_toolchains": ["//test/fixtures/toolchains:toolchain_macos_arm64_with_sdkroot"],
})

_explicit_command_line_test = make_action_command_line_test_rule(_explicit_config)
_implicit_command_line_test = make_action_command_line_test_rule(_implicit_config)
_explicit_json_command_line_test = make_action_command_line_test_rule(_explicit_json_config)
_explicit_without_pcm_command_line_test = make_action_command_line_test_rule(_explicit_without_pcm_config)
_explicit_inputs_test = make_action_inputs_test_rule(_explicit_config)
_implicit_inputs_test = make_action_inputs_test_rule(_implicit_config)
_explicit_json_inputs_test = make_action_inputs_test_rule(_explicit_json_config)
_explicit_without_pcm_inputs_test = make_action_inputs_test_rule(_explicit_without_pcm_config)
_explicit_provider_test = make_provider_test_rule(_explicit_config)

def _mixed_language_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    instrumented_files = sorted([
        file.short_path
        for file in target[InstrumentedFilesInfo].instrumented_files.to_list()
    ])

    asserts.equals(
        env,
        sorted(ctx.attr.expected_instrumented_files),
        instrumented_files,
    )

    return analysistest.end(env)

mixed_language_coverage_test = analysistest.make(
    _mixed_language_coverage_test_impl,
    attrs = {
        "expected_instrumented_files": attr.string_list(),
    },
    config_settings = {
        "//command_line_option:collect_code_coverage": "true",
    },
)

def _mixed_language_module_label_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    direct_modules = target[SwiftInfo].direct_modules

    asserts.equals(
        env,
        [target.label],
        [module.label for module in direct_modules],
    )

    return analysistest.end(env)

mixed_language_module_label_test = analysistest.make(
    _mixed_language_module_label_test_impl,
)

def mixed_language_test_suite(name, tags = []):
    """Test suite for mixed-language library behavior.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    build_test(
        name = "{}_build_test".format(name),
        targets = ["//test/fixtures/mixed_language:MixedLibraryWithTestOnlyDeps"],
        tags = all_tags,
    )

    mixed_language_coverage_test(
        name = "{}_coverage_test".format(name),
        expected_instrumented_files = [
            "test/fixtures/mixed_language/MixedLibrary.h",
            "test/fixtures/mixed_language/MixedLibrary.m",
            "test/fixtures/mixed_language/MixedLibrary.swift",
            "test/fixtures/mixed_language/TestOnlyDep.h",
        ],
        target_under_test = "//test/fixtures/mixed_language:MixedLibraryWithTestOnlyDeps",
        tags = all_tags,
    )

    mixed_language_module_label_test(
        name = "{}_module_label_test".format(name),
        target_under_test = "//test/fixtures/mixed_language:MixedLibraryWithTestOnlyDeps",
        tags = all_tags,
    )

    _explicit_command_line_test(
        name = "{}_public_headers_explicit_flags".format(name),
        expected_argv = [
            "-import-underlying-module",
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/xplatform/mixed_c_swift/simple_library_modulemap/_/module.modulemap",
            "-Xcc -fmodule-file=MixedCSwiftLibrary=$(BIN_DIR)/examples/xplatform/mixed_c_swift/simple_library.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    _explicit_inputs_test(
        name = "{}_public_headers_explicit_inputs".format(name),
        expected_inputs = [
            "examples/xplatform/mixed_c_swift/simple_library_modulemap/_/module.modulemap",
            "simple_library.swift.pcm",
        ],
        not_expected_inputs = ["Private.h"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    # The generic toolchain, also used on Linux, doesn't register a Clang
    # precompile action. Requesting explicit modules must still stage the textual
    # map and headers when no PCM can be produced.
    _explicit_without_pcm_command_line_test(
        name = "{}_public_headers_explicit_without_pcm_flags".format(name),
        expected_argv = [
            "-import-underlying-module",
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/xplatform/mixed_c_swift/simple_library_modulemap/_/module.modulemap",
        ],
        not_expected_argv = [
            "-Xcc -fmodule-file=MixedCSwiftLibrary=$(BIN_DIR)/examples/xplatform/mixed_c_swift/simple_library.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    _explicit_without_pcm_inputs_test(
        name = "{}_public_headers_explicit_without_pcm_inputs".format(name),
        expected_inputs = [
            "examples/xplatform/mixed_c_swift/simple_library_modulemap/_/module.modulemap",
            "Private.h",
        ],
        not_expected_inputs = ["simple_library.swift.pcm"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    _implicit_command_line_test(
        name = "{}_public_headers_implicit_flags".format(name),
        expected_argv = [
            "-import-underlying-module",
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/xplatform/mixed_c_swift/simple_library_modulemap/_/module.modulemap",
        ],
        not_expected_argv = [
            "-Xcc -fmodule-file=MixedCSwiftLibrary=$(BIN_DIR)/examples/xplatform/mixed_c_swift/simple_library.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    _implicit_inputs_test(
        name = "{}_public_headers_implicit_inputs".format(name),
        expected_inputs = [
            "examples/xplatform/mixed_c_swift/simple_library_modulemap/_/module.modulemap",
            "Private.h",
        ],
        not_expected_inputs = ["simple_library.swift.pcm"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    _implicit_inputs_test(
        name = "{}_private_headers_implicit_inputs".format(name),
        expected_inputs = [
            "examples/xplatform/mixed_c_swift/simple_modulemap/_/module.modulemap",
            "Private.h",
        ],
        not_expected_inputs = ["simple.swift.pcm"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple",
    )

    provider_test(
        name = "{}_public_headers_without_generated_header".format(name),
        expected_files = ["examples/xplatform/mixed_c_swift/Private.h"],
        field = "compilation_context.direct_public_headers",
        provider = "CcInfo",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    provider_test(
        name = "{}_headerless_library_has_no_generated_header".format(name),
        expected_files = ["-simple_library-Swift.h"],
        field = "direct_modules.swift.generated_header!",
        provider = "SwiftInfo",
        tags = all_tags,
        target_under_test = "//examples/xplatform/mixed_c_swift:simple_library",
    )

    _explicit_command_line_test(
        name = "{}_generated_header_explicit_flags".format(name),
        expected_argv = [
            "-import-underlying-module",
            "-Xcc -ivfsoverlay -Xcc $(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_objs/unextended-module-overlay.yaml",
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.modulemap",
            "-Xcc -fmodule-file=Multiplier=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier.swift.pcm",
        ],
        not_expected_argv = [
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.incomplete.modulemap",
            "-Xcc -fmodule-file=Multiplier=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier.swift.incomplete.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    _explicit_inputs_test(
        name = "{}_generated_header_explicit_inputs".format(name),
        expected_inputs = [
            "examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.incomplete.modulemap",
            "Multiplier.swift.incomplete.pcm",
            "unextended-module-overlay.yaml",
        ],
        not_expected_inputs = [
            "Multiplier.h",
            "Multiplier-Swift.h",
            "Multiplier.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    _implicit_command_line_test(
        name = "{}_generated_header_implicit_flags".format(name),
        expected_argv = [
            "-import-underlying-module",
            "-Xcc -ivfsoverlay -Xcc $(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_objs/unextended-module-overlay.yaml",
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.modulemap",
        ],
        not_expected_argv = [
            "-Xcc -fmodule-file=Multiplier=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    _implicit_inputs_test(
        name = "{}_generated_header_implicit_inputs".format(name),
        expected_inputs = [
            "examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.incomplete.modulemap",
            "Multiplier.h",
            "unextended-module-overlay.yaml",
        ],
        not_expected_inputs = [
            "Multiplier-Swift.h",
            "Multiplier.swift.incomplete.pcm",
            "Multiplier.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    _explicit_provider_test(
        name = "{}_generated_header_propagates_complete_pcm".format(name),
        expected_files = ["examples/apple/mixed_c_swift/generated_hdr/Multiplier.swift.pcm"],
        field = "direct_modules.clang.precompiled_module",
        provider = "SwiftInfo",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    _explicit_json_command_line_test(
        name = "{}_generated_header_explicit_json_flags".format(name),
        expected_argv = [
            "-import-underlying-module",
            "-Xcc -ivfsoverlay -Xcc $(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_objs/unextended-module-overlay.yaml",
            "-Xcc -fmodule-map-file=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.modulemap",
            "-Xcc -fmodule-file=Multiplier=$(BIN_DIR)/examples/apple/mixed_c_swift/generated_hdr/Multiplier.swift.pcm",
        ],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    _explicit_json_inputs_test(
        name = "{}_generated_header_explicit_json_inputs".format(name),
        expected_inputs = [
            "examples/apple/mixed_c_swift/generated_hdr/Multiplier_modulemap/_/module.incomplete.modulemap",
            "Multiplier.swift.incomplete.pcm",
            "unextended-module-overlay.yaml",
        ],
        not_expected_inputs = ["Multiplier-Swift.h", "Multiplier.swift.pcm"],
        mnemonic = "SwiftCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
    )

    build_test(
        name = "{}_first_class_round_trip".format(name),
        targets = [
            "//examples/apple/mixed_c_swift/generated_hdr:Multiplier",
            "//examples/xplatform/mixed_c_swift:simple_library",
        ],
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
    )

    _implicit_command_line_test(
        name = "{}_c_compilation_uses_direct_strict_includes".format(name),
        expected_argv = ["-iquotestrict/public", "-iquotestrict/private"],
        not_expected_argv = ["-iquotestrict/transitive"],
        mnemonic = "ObjcCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/mixed_language:StrictMixedLibrary",
    )

    _implicit_command_line_test(
        name = "{}_c_compilation_does_not_inherit_strict_includes".format(name),
        not_expected_argv = [
            "-iquotestrict/public",
            "-iquotestrict/private",
            "-iquotestrict/transitive",
        ],
        mnemonic = "ObjcCompile",
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/mixed_language:StrictMixedConsumer",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
