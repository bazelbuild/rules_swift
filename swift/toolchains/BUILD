load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

licenses(["notice"])

APPLE_PLATFORMS_CONSTRAINTS = {
    "darwin_arm64": [
        "@platforms//os:macos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:device",
    ],
    "darwin_arm64e": [
        "@platforms//os:macos",
        "@platforms//cpu:arm64e",
        "@apple_support//constraints:device",
    ],
    "darwin_x86_64": [
        "@platforms//os:macos",
        "@platforms//cpu:x86_64",
        "@apple_support//constraints:device",
    ],
    "ios_arm64": [
        "@platforms//os:ios",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:device",
    ],
    "ios_arm64e": [
        "@platforms//os:ios",
        "@platforms//cpu:arm64e",
        "@apple_support//constraints:device",
    ],
    "ios_x86_64": [
        "@platforms//os:ios",
        "@platforms//cpu:x86_64",
        "@apple_support//constraints:simulator",
    ],
    "ios_sim_arm64": [
        "@platforms//os:ios",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:simulator",
    ],
    "tvos_arm64": [
        "@platforms//os:tvos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:device",
    ],
    "tvos_x86_64": [
        "@platforms//os:tvos",
        "@platforms//cpu:x86_64",
        "@apple_support//constraints:simulator",
    ],
    "tvos_sim_arm64": [
        "@platforms//os:tvos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:simulator",
    ],
    "visionos_arm64": [
        "@platforms//os:visionos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:device",
    ],
    "visionos_sim_arm64": [
        "@platforms//os:visionos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:simulator",
    ],
    "watchos_arm64": [
        "@platforms//os:watchos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:simulator",
    ],
    "watchos_device_arm64": [
        "@platforms//os:watchos",
        "@platforms//cpu:arm64",
        "@apple_support//constraints:device",
    ],
    "watchos_device_arm64e": [
        "@platforms//os:watchos",
        "@platforms//cpu:arm64e",
        "@apple_support//constraints:device",
    ],
    "watchos_arm64_32": [
        "@platforms//os:watchos",
        "@platforms//cpu:arm64_32",
        "@apple_support//constraints:device",
    ],
    "watchos_armv7k": [
        "@platforms//os:watchos",
        "@platforms//cpu:armv7k",
        "@apple_support//constraints:device",
    ],
    "watchos_x86_64": [
        "@platforms//os:watchos",
        "@platforms//cpu:x86_64",
        "@apple_support//constraints:simulator",
    ],
}

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
        "@rules_cc//cc:find_cc_toolchain_bzl",
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
        "@rules_cc//cc:find_cc_toolchain_bzl",
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
    toolchain = "@rules_swift_local_config//:linux-toolchain",
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
    toolchain = "@rules_swift_local_config//:linux-toolchain",
    toolchain_type = "//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

[
    toolchain(
        name = "xcode-sdk-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = "@rules_swift_local_config//:xcode-sdk-toolchain",
        toolchain_type = "//toolchains:sdk_toolchain_type",
        visibility = ["//visibility:public"],
    )
    for arch, constraints in APPLE_PLATFORMS_CONSTRAINTS.items()
]

[
    toolchain(
        name = "xcode-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = "@rules_swift_local_config//:xcode-toolchain",
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
    toolchain = "@rules_swift_local_config//:windows-toolchain",
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

bzl_library(
    name = "swift_tools",
    srcs = ["swift_tools.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//swift:providers"],
)
