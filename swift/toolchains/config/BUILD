load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

package(
    default_visibility = [
        "//swift/internal:__pkg__",
        "//swift/toolchains:__pkg__",
    ],
)

exports_files(["const_extract_protocols.json"])

bzl_library(
    name = "compile_module_interface_config",
    srcs = ["compile_module_interface_config.bzl"],
    deps = [
        "//swift/internal:actions",
        "//swift/internal:toolchain_config",
    ],
)

# Consumed by Bazel integration tests.
filegroup(
    name = "for_bazel_tests",
    testonly = 1,
    srcs = glob(["**"]),
    visibility = [
        "//swift/toolchains:__pkg__",
    ],
)
