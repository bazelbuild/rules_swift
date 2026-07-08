load(
    "@apple_support//configs:platforms.bzl",
    "APPLE_PLATFORMS_CONSTRAINTS",
)
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_swift//swift/toolchains:xcode_swift_toolchain.bzl", "xcode_swift_toolchain")
load(
    "//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS",
)

licenses(["notice"])

constraint_setting(
    name = "swift_sdk",
    visibility = ["//visibility:public"],
)

constraint_value(
    name = "static_linux",
    constraint_setting = ":swift_sdk",
    visibility = ["//visibility:public"],
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

_XCODE_FEATURE_VALUES = [
    # TODO: This should be removed so that private headers can be used with
    # explicit modules, but the build targets for CgRPC need to be cleaned
    # up first because they contain C++ code.
    SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS,
]

xcode_swift_toolchain(
    name = "xcode-sdk-toolchain",
    features = _XCODE_FEATURE_VALUES,
    tags = ["manual"],
)

xcode_swift_toolchain(
    name = "xcode-toolchain",
    cross_import_overlays = ["@system_sdk//:all_cross_import_overlays"],
    features = _XCODE_FEATURE_VALUES,
    implicit_system_modules = "@system_sdk//:implicit_modules",
    system_modules = "@system_sdk//:all_modules",
    tags = ["manual"],
)

[
    toolchain(
        name = "xcode-sdk-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = ":xcode-sdk-toolchain",
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
        toolchain = ":xcode-toolchain",
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

toolchain(
    name = "windows-swift-toolchain-aarch64",
    exec_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:aarch64",
    ],
    target_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:aarch64",
    ],
    toolchain = "@rules_swift_local_config//:windows-toolchain",
    toolchain_type = "//toolchains:toolchain_type",
    visibility = ["//visibility:public"],
)

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
    name = "swift_tools",
    srcs = ["swift_tools.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//swift:providers"],
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
