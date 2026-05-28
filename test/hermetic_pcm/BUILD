load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift.bzl", "system_swiftinterface")
load("//swift:swift_compiler_plugin.bzl", "swift_compiler_plugin")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//swift:swift_library.bzl", "swift_library")
load("//test:transitions.bzl", "transition_binary")
load(":extract_pcm.bzl", "extract_pcm")
load(":extract_swiftmodule.bzl", "extract_swiftmodule")
load(":xcode_version_at_least.bzl", "xcode_version_at_least")

xcode_version_at_least(
    name = "xcode_at_least_26_4",
    minimum_version = "26.4",
)

config_setting(
    name = "supports_hermetic_swiftmodule",
    flag_values = {":xcode_at_least_26_4": "True"},
)

transition_binary(
    name = "foundation_pcm",
    target = "@system_sdk//:Foundation_clang",
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    transitive_features = [
        "swift.use_c_modules",
        "swift.emit_c_module",
    ],
)

sh_test(
    name = "hermetic_pcm_test",
    srcs = ["check_hermetic_pcm.sh"],
    args = ["$(rootpath :foundation_pcm)"],
    data = [":foundation_pcm"],
)

swift_interop_hint(
    name = "SimpleObj_hint",
    module_name = "SimpleObj",
)

objc_library(
    name = "SimpleObj",
    srcs = ["SimpleObj.m"],
    hdrs = ["SimpleObj.h"],
    aspect_hints = [":SimpleObj_hint"],
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["@system_sdk//:Foundation"],
)

extract_pcm(
    name = "simple_obj_pcm",
    target = ":SimpleObj",
)

sh_test(
    name = "hermetic_objc_pcm_test",
    srcs = ["check_hermetic_pcm.sh"],
    args = ["$(rootpath :simple_obj_pcm)"],
    data = [":simple_obj_pcm"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

swift_library(
    name = "SimpleSwift",
    srcs = ["SimpleSwift.swift"],
    generates_header = True,
    module_name = "SimpleSwift",
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

extract_pcm(
    name = "simple_swift_header_pcm",
    target = ":SimpleSwift",
)

sh_test(
    name = "hermetic_swift_header_pcm_test",
    srcs = ["check_hermetic_pcm.sh"],
    args = ["$(rootpath :simple_swift_header_pcm)"],
    data = [":simple_swift_header_pcm"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

swift_library(
    name = "Downstream",
    srcs = ["Downstream.swift"],
    module_name = "Downstream",
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["@system_sdk//:Foundation"],
)

extract_swiftmodule(
    name = "downstream_swiftmodule",
    target = ":Downstream",
)

# A swiftmodule that references PCMs must not have absolute paths to them or
# Xcode in the output or debugging will fail
sh_test(
    name = "hermetic_downstream_swiftmodule_test",
    srcs = ["check_hermetic_swiftmodule.sh"],
    args = ["$(rootpath :downstream_swiftmodule)"],
    data = [":downstream_swiftmodule"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

extract_swiftmodule(
    name = "downstream_explicit_swiftmodule",
    extra_features = ["swift.use_explicit_swift_module_map"],
    target = ":Downstream",
)

sh_test(
    name = "hermetic_downstream_explicit_swiftmodule_test",
    srcs = ["check_hermetic_swiftmodule.sh"],
    args = ["$(rootpath :downstream_explicit_swiftmodule)"],
    data = [":downstream_explicit_swiftmodule"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

extract_swiftmodule(
    name = "testing_swiftmodule",
    target = "@system_sdk//:Testing",
)

# Direct system Swift modules should not embed absolute Xcode paths either,
# including the swiftinterface source path serialized into the swiftmodule.
sh_test(
    name = "hermetic_testing_swiftmodule_test",
    srcs = ["check_hermetic_swiftmodule.sh"],
    args = [
        "$(rootpath :testing_swiftmodule)",
        "--no-default-expected",
        "Testing",
    ],
    data = [":testing_swiftmodule"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

system_swiftinterface(
    name = "non_xcode_swiftinterface_module",
    module_name = "LowerVersionLib",
    modules = [
        "@system_sdk//:Foundation",
        "@system_sdk//:Swift",
        "@system_sdk//:SwiftShims",
        "@system_sdk//:_Concurrency",
        "@system_sdk//:_StringProcessing",
        "@system_sdk//:_SwiftConcurrencyShims",
    ],
    swiftinterface = "//test/fixtures/precompiled_modules:LowerVersionLib.swiftinterface",
    target_compatible_with = ["@platforms//os:macos"],
)

extract_swiftmodule(
    name = "non_xcode_swiftinterface_swiftmodule",
    target = ":non_xcode_swiftinterface_module",
)

# A swiftinterface outside DEVELOPER_DIR can come from an external framework.
# It must still be compiled through a relative path so the resulting swiftmodule
# does not serialize a host-specific absolute source path.
sh_test(
    name = "non_xcode_swiftinterface_swiftmodule_test",
    srcs = ["check_hermetic_swiftmodule.sh"],
    args = [
        "$(rootpath :non_xcode_swiftinterface_swiftmodule)",
        "--no-default-expected",
        "test/fixtures/precompiled_modules/LowerVersionLib.swiftinterface",
    ],
    data = [":non_xcode_swiftinterface_swiftmodule"],
    target_compatible_with = ["@platforms//os:macos"],
)

# Same hermeticity check, but the consumer swift_library depends on a
# `swift_compiler_plugin`. Plugins get serialized into the swiftmodule via
# `<executable>#<server>#<module>` and should be relative
swift_compiler_plugin(
    name = "noop_plugin",
    srcs = ["NoopMacroPlugin.swift"],
    module_name = "NoopMacroPlugin",
)

swift_library(
    name = "DownstreamWithPlugin",
    srcs = ["DownstreamWithPlugin.swift"],
    module_name = "DownstreamWithPlugin",
    plugins = [":noop_plugin"],
    target_compatible_with = select({
        "@build_bazel_apple_support//configs:apple": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    deps = ["@system_sdk//:Foundation"],
)

extract_swiftmodule(
    name = "downstream_with_plugin_swiftmodule",
    target = ":DownstreamWithPlugin",
)

sh_test(
    name = "hermetic_downstream_with_plugin_swiftmodule_test",
    srcs = ["check_hermetic_swiftmodule.sh"],
    args = [
        "$(rootpath :downstream_with_plugin_swiftmodule)",
        "test/hermetic_pcm/noop_plugin#NoopMacroPlugin",  # Make sure the plugin path is included
    ],
    data = [":downstream_with_plugin_swiftmodule"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

extract_swiftmodule(
    name = "downstream_with_plugin_explicit_swiftmodule",
    extra_features = ["swift.use_explicit_swift_module_map"],
    target = ":DownstreamWithPlugin",
)

sh_test(
    name = "hermetic_downstream_with_plugin_explicit_swiftmodule_test",
    srcs = ["check_hermetic_swiftmodule.sh"],
    args = [
        "$(rootpath :downstream_with_plugin_explicit_swiftmodule)",
        "test/hermetic_pcm/noop_plugin#NoopMacroPlugin",  # Make sure the plugin path is included
    ],
    data = [":downstream_with_plugin_explicit_swiftmodule"],
    target_compatible_with = select({
        ":supports_hermetic_swiftmodule": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
)

bzl_library(
    name = "extract_pcm",
    srcs = ["extract_pcm.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        "//swift:providers",
        "//swift:swift_clang_module_aspect",
    ],
)

bzl_library(
    name = "extract_swiftmodule",
    srcs = ["extract_swiftmodule.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//swift:providers"],
)

bzl_library(
    name = "xcode_version_at_least",
    srcs = ["xcode_version_at_least.bzl"],
    visibility = ["//visibility:public"],
)
