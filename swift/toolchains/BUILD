load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(
    "@build_bazel_apple_support//configs:platforms.bzl",
    "APPLE_PLATFORMS_CONSTRAINTS",
)

licenses(["notice"])

bzl_library(
    name = "swift_toolchain",
    srcs = ["swift_toolchain.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        "//swift:providers",
        "//swift/internal:action_names",
        "//swift/internal:attrs",
        "//swift/internal:autolinking",
        "//swift/internal:debugging",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:providers",
        "//swift/internal:target_triples",
        "//swift/internal:utils",
        "//swift/internal:wmo",
        "//swift/toolchains/config:action_config",
        "//swift/toolchains/config:all_actions_config",
        "//swift/toolchains/config:compile_config",
        "//swift/toolchains/config:symbol_graph_config",
        "//swift/toolchains/config:synthesize_interface_config",
        "//swift/toolchains/config:tool_config",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "xcode_swift_toolchain",
    srcs = ["xcode_swift_toolchain.bzl"],
    visibility = ["//swift:__subpackages__"],
    deps = [
        "//swift:providers",
        "//swift/internal:action_names",
        "//swift/internal:attrs",
        "//swift/internal:feature_names",
        "//swift/internal:features",
        "//swift/internal:providers",
        "//swift/internal:target_triples",
        "//swift/internal:utils",
        "//swift/internal:wmo",
        "//swift/toolchains/config:action_config",
        "//swift/toolchains/config:all_actions_config",
        "//swift/toolchains/config:compile_config",
        "//swift/toolchains/config:compile_module_interface_config",
        "//swift/toolchains/config:symbol_graph_config",
        "//swift/toolchains/config:synthesize_interface_config",
        "//swift/toolchains/config:tool_config",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
        "@bazel_tools//tools/cpp:toolchain_utils.bzl",
        "@rules_cc//cc/common",
    ],
)

toolchain(
    name = "linux-swift-toolchain_x86_64",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    toolchain = "@build_bazel_rules_swift_local_config//:linux-toolchain",
    toolchain_type = "//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "linux-swift-toolchain_aarch64",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
    toolchain = "@build_bazel_rules_swift_local_config//:linux-toolchain",
    toolchain_type = "//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

[
    toolchain(
        name = "xcode-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = "@build_bazel_rules_swift_local_config//:xcode-toolchain",
        toolchain_type = "//toolchains:toolchain_type",
        visibility = ["//visibility:public"],
    )
    for arch, constraints in APPLE_PLATFORMS_CONSTRAINTS.items()
]

toolchain(
    name = "windows-swift-toolchain-x86_64",
    exec_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
    toolchain = "@build_bazel_rules_swift_local_config//:windows-toolchain",
    toolchain_type = "//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = True,
    srcs = glob(["**"]) + [
        "//swift/toolchains/config:for_bazel_tests",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
)
