load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("//swift:swift_binary.bzl", "swift_binary")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_test.bzl", "swift_test")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":force_features.bzl", "force_features_binary", "force_features_test")

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
    target_compatible_with = ["@platforms//os:macos"],
    deps = [
        "@system_sdk//:Foundation",
    ],
)

force_features_binary(
    name = "hello_with_explicit_deps_transitioned",
    binary = ":hello_with_explicit_deps_bin",
    tags = FIXTURE_TAGS,
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
    target_compatible_with = ["@platforms//os:macos"],
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

force_features_binary(
    name = "objc_interop_bin_transitioned",
    binary = ":objc_interop_bin",
    tags = FIXTURE_TAGS,
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
    target_compatible_with = ["@platforms//os:macos"],
)

swift_compiler_plugin(
    name = "stub_plugin",
    srcs = ["StubPlugin.swift"],
    module_name = "StubPlugin",
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
)

swift_binary(
    name = "objc_interop_implicit_bin",
    srcs = ["greeter_main.swift"],
    plugins = [":stub_plugin"],
    tags = FIXTURE_TAGS,
    deps = [":GreeterImplicit"],
)

force_features_binary(
    name = "objc_interop_implicit_bin_transitioned",
    binary = ":objc_interop_implicit_bin",
    tags = FIXTURE_TAGS,
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
    deps = [
        "@system_sdk//:SwiftShims",
        "@system_sdk//:XCTest",
    ],
)

force_features_test(
    name = "simple_xctest_transitioned",
    binary = ":simple_xctest",
    tags = FIXTURE_TAGS,
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "-swift.add_default_precompiled_modules",
    ],
)

# Imports C-only modules whose modulemaps live under `<sdk>/usr/include/<name>.modulemap`
swift_binary(
    name = "c_module_imports",
    srcs = ["c_module_imports.swift"],
    tags = FIXTURE_TAGS,
    target_compatible_with = ["@platforms//os:macos"],
)

force_features_binary(
    name = "c_module_imports_transitioned",
    binary = ":c_module_imports",
    tags = FIXTURE_TAGS,
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
        "swift.add_default_precompiled_modules",
    ],
)
