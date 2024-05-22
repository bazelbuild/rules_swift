load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

package(
    default_visibility = ["//visibility:public"],
)

licenses(["notice"])

bzl_library(
    name = "swift_toolchain",
    srcs = ["swift_toolchain.bzl"],
    deps = [
        "//swift:providers",
        "//swift/internal:action_names",
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
        "//swift/toolchains/config:default_warnings_as_errors",
        "//swift/toolchains/config:symbol_graph_config",
        "//swift/toolchains/config:tool_config",
        "//third_party/unsupported_toolchains/swift/build_defs:glibc_module_bzl",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "xcode_swift_toolchain",
    srcs = ["xcode_swift_toolchain.bzl"],
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
        "//swift/toolchains/config:default_warnings_as_errors",
        "//swift/toolchains/config:symbol_graph_config",
        "//swift/toolchains/config:tool_config",
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
    ],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]) + [
        "//swift/toolchains/config:for_bazel_tests",
    ],
    visibility = [
        "//swift:__pkg__",
    ],
)
