load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//mixed_language:mixed_language_library.bzl", "mixed_language_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")
load("//swift:swift_import.bzl", "swift_import")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load(
    "//test:transitions.bzl",
    "transition_binary",
    "transition_test",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load("//test/rules:swift_verify_test.bzl", "swift_verify_test")
load(":cross_platform.bzl", "cross_platform_targets")

package(default_visibility = ["//test:__subpackages__"])

licenses(["notice"])

swift_binary(
    name = "hello",
    srcs = ["main.swift"],
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "hello_with_explicit_deps_bin",
    srcs = ["main.swift"],
    features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        "@system_sdk//:Foundation",
    ],
)

transition_binary(
    name = "hello_with_explicit_deps_transitioned",
    tags = FIXTURE_TAGS,
    target = ":hello_with_explicit_deps_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_interop_hint(
    name = "Greeter_hint",
    module_name = "Greeter",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "Greeter",
    srcs = ["Greeter.m"],
    hdrs = ["Greeter.h"],
    aspect_hints = [":Greeter_hint"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["@system_sdk//:Foundation"],
)

swift_binary(
    name = "objc_interop_bin",
    srcs = ["greeter_main.swift"],
    tags = FIXTURE_TAGS,
    deps = [
        ":Greeter",
    ],
)

transition_binary(
    name = "objc_interop_bin_transitioned",
    tags = FIXTURE_TAGS,
    target = ":objc_interop_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

# Implicit dependencies with objc interop
swift_interop_hint(
    name = "GreeterImplicit_hint",
    module_name = "Greeter",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "GreeterImplicit",
    srcs = ["Greeter.m"],
    hdrs = ["Greeter.h"],
    aspect_hints = [":GreeterImplicit_hint"],
    copts = ["-fno-stack-protector"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

swift_compiler_plugin(
    name = "stub_plugin",
    srcs = ["StubPlugin.swift"],
    module_name = "StubPlugin",
    tags = FIXTURE_TAGS,
)

swift_binary(
    name = "objc_interop_implicit_bin",
    srcs = ["greeter_main.swift"],
    plugins = [":stub_plugin"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [":GreeterImplicit"],
)

transition_binary(
    name = "objc_interop_implicit_bin_transitioned",
    tags = FIXTURE_TAGS,
    target = ":objc_interop_implicit_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
    ],
)

# Currently XCTest is clang-only and that requires specific dependency tree
# handling for the output of scan-dependencies
swift_test(
    name = "simple_xctest",
    srcs = ["SimpleXCTest.swift"],
    discover_tests = False,
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        "@system_sdk//:SwiftShims",
        "@system_sdk//:XCTest",
    ],
)

transition_test(
    name = "simple_xctest_transitioned",
    tags = FIXTURE_TAGS,
    target = ":simple_xctest",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

# Test modules don't have prebuilt swiftmodule files so they are handled differently
swift_test(
    name = "xctest_with_testing",
    srcs = ["XCTestWithTesting.swift"],
    discover_tests = False,
    tags = FIXTURE_TAGS,
)

transition_test(
    name = "xctest_with_testing_transitioned",
    compilation_mode = "dbg",  # forces a different stack protector mode which can expose issues
    tags = FIXTURE_TAGS,
    target = ":xctest_with_testing",
    transitive_features = [
        "swift.emit_c_module",
        "swift.use_c_modules",
        "swift.use_explicit_swift_module_map",
    ],
)

# Imports C-only modules whose modulemaps live under `<sdk>/usr/include/<name>.modulemap`
swift_binary(
    name = "c_module_imports",
    srcs = ["c_module_imports.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

transition_binary(
    name = "c_module_imports_transitioned",
    tags = FIXTURE_TAGS,
    target = ":c_module_imports",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
    ],
)

# Test `mixed_language_library` with explicit modules
mixed_language_library(
    name = "MixedGreeter",
    hdrs = ["MixedGreeter.h"],
    clang_srcs = ["MixedGreeter.m"],
    module_name = "MixedGreeter",
    swift_srcs = ["MixedGreeter.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

swift_binary(
    name = "mixed_language_bin",
    srcs = ["mixed_greeter_main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":MixedGreeter"],
)

transition_binary(
    name = "mixed_language_bin_transitioned",
    tags = FIXTURE_TAGS,
    target = ":mixed_language_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
    ],
)

mixed_language_library(
    name = "MixedGreeterExplicit",
    hdrs = ["MixedGreeter.h"],
    clang_srcs = ["MixedGreeter.m"],
    module_name = "MixedGreeter",
    swift_srcs = ["MixedGreeter.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["@system_sdk//:Foundation"],
)

swift_binary(
    name = "mixed_language_explicit_bin",
    srcs = ["mixed_greeter_main.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        ":MixedGreeterExplicit",
        "@system_sdk//:Foundation",
    ],
)

transition_binary(
    name = "mixed_language_explicit_bin_transitioned",
    tags = FIXTURE_TAGS,
    target = ":mixed_language_explicit_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_interop_hint(
    name = "ExtensionUnavailableObjC_hint",
    module_name = "ExtensionUnavailableObjC",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "ExtensionUnavailableObjC",
    srcs = ["ExtensionUnavailableObjC.m"],
    hdrs = ["ExtensionUnavailableObjC.h"],
    aspect_hints = [":ExtensionUnavailableObjC_hint"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@system_sdk//:Foundation"],
)

swift_verify_test(
    name = "foundation_requires_explicit_dep",
    srcs = ["foundation_requires_explicit_dep.swift"],
    module_name = "FoundationRequiresExplicitDep",
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["@system_sdk//:CoreFoundation"],
)

transition_test(
    name = "foundation_requires_explicit_dep_transitioned",
    tags = FIXTURE_TAGS,
    target = ":foundation_requires_explicit_dep",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_verify_test(
    name = "application_extension_unavailable",
    srcs = ["ApplicationExtensionLib.swift"],
    copts = [
        "-application-extension",
        "-Xfrontend",
        "-verify-ignore-unrelated",
        "-Xcc",
        "-fno-application-extension",
    ],
    module_name = "ApplicationExtensionLib",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":ExtensionUnavailableObjC",
        "@system_sdk//:Foundation",
    ],
)

transition_test(
    name = "application_extension_unavailable_transitioned",
    tags = FIXTURE_TAGS,
    target = ":application_extension_unavailable",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_library(
    name = "can_import_undeclared_sdk_module",
    srcs = ["can_import_undeclared_sdk_module.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@system_sdk//:Foundation"],
)

transition_binary(
    name = "can_import_undeclared_sdk_module_transitioned",
    tags = FIXTURE_TAGS,
    target = ":can_import_undeclared_sdk_module",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

cross_platform_targets(tags = FIXTURE_TAGS)

swift_import(
    name = "LowerVersionLib",
    module_name = "LowerVersionLib",
    swiftinterface = "LowerVersionLib.swiftinterface",  # NOTE: The macOS version in this file _must_ not be the same one we use globally, that is the behavior we're testing
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
)

swift_binary(
    name = "lower_version_bin",
    srcs = ["lower_version_main.swift"],
    tags = FIXTURE_TAGS,
    deps = [":LowerVersionLib"],
)

transition_binary(
    name = "lower_version_bin_transitioned",
    tags = FIXTURE_TAGS,
    target = ":lower_version_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
        "swift.use_explicit_swift_module_map",  # NOTE: This is required to make sure no implicit modules are found
    ],
)

swift_library(
    name = "min_os_lib",
    srcs = ["min_os_lib.swift"],
    module_name = "MinOSLib",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":Greeter",
        "@system_sdk//:Foundation",
    ],
)

transition_binary(
    name = "min_os_lib_at_13",
    minimum_os = "13.0",  # NOTE: Needs to be different from --macos_minimum_os in .bazelrc
    tags = FIXTURE_TAGS,
    target = ":min_os_lib",
)

swift_binary(
    name = "min_os_bin",
    srcs = ["min_os_main.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":min_os_lib_at_13",
        "@system_sdk//:Foundation",
    ],
)

# Testing the diamond dependency with different OS versions on
# @system_sdk//:Foundation through Greeter's PCM. If we do this wrong Greeter's
# PCM will see the wrong Foundation.pcm when being imported.
transition_binary(
    name = "min_os_bin_transitioned",
    tags = FIXTURE_TAGS,
    target = ":min_os_bin",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_test(
    name = "linking_cross_import_overlay",
    srcs = [
        # NOTE: The current API requires a cross import overlay, but we might
        # need to find another one in the future if this one moves.
        "cross_import_overlay_pollution.swift",
        "main.swift",
    ],
    discover_tests = False,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        "@system_sdk//:AppKit",
        "@system_sdk//:Testing",
    ],
)

transition_test(
    name = "linking_cross_import_overlay_transitioned",
    testonly = True,
    tags = FIXTURE_TAGS,
    target = ":cross_import_overlay_dep_pollution",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
        # NOTE: Must not enable swift.use_explicit_swift_module_map which affects linking logic
    ],
)

swift_binary(
    name = "cross_import_overlay",
    srcs = ["main.swift"],
    copts = ["-suppress-warnings"],
    tags = FIXTURE_TAGS,
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = [
        "@system_sdk//:MapKit",
        "@system_sdk//:SwiftUI",
    ],
)

transition_binary(
    name = "cross_import_overlay_transitioned",
    tags = FIXTURE_TAGS,
    target = ":cross_import_overlay",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

swift_library(
    name = "pollute_appkit_dep",
    srcs = ["empty.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = ["@system_sdk//:AppKit"],  # This dep becomes available to consumers who don't enable swift.layering_check
)

swift_test(
    name = "cross_import_overlay_dep_pollution",
    srcs = ["main.swift"],
    discover_tests = False,
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        ":pollute_appkit_dep",
        "@system_sdk//:Testing",  # Testing + AppKit currently have a cross import overlay which must be imported
    ],
)

transition_test(
    name = "cross_import_overlay_dep_pollution_transitioned",
    testonly = True,
    minimum_os = "26.0",
    tags = FIXTURE_TAGS,
    target = ":cross_import_overlay_dep_pollution",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
        "swift.use_explicit_swift_module_map",
    ],
)

transition_test(
    name = "cross_import_overlay_dep_pollution_default_precompiled_modules_transitioned",
    testonly = True,
    minimum_os = "26.0",
    tags = FIXTURE_TAGS,
    target = ":cross_import_overlay_dep_pollution",
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
        "swift.use_explicit_swift_module_map",
    ],
)

bzl_library(
    name = "cross_platform",
    srcs = ["cross_platform.bzl"],
    deps = ["//test:transitions"],
)
