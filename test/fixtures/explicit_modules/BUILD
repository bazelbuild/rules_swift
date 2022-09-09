load("//swift:swift.bzl", "swift_c_module", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

###############################################################################
# Fixtures for testing explicit clang module compilation.

swift_library(
    name = "simple",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":shims"],
)

swift_c_module(
    name = "shims",
    module_name = "SwiftShims",
    system_module_map = "__BAZEL_XCODE_SDKROOT__/usr/lib/swift/shims/module.modulemap",
    tags = FIXTURE_TAGS,
)

swift_c_module(
    name = "Darwin",
    module_name = "Darwin",
    system_module_map = "__BAZEL_XCODE_SDKROOT__/usr/include/module.modulemap",
    tags = FIXTURE_TAGS,
    deps = [
        ":_Builtin_stddef_max_align_t",
    ],
)

swift_c_module(
    name = "_Builtin_stddef_max_align_t",
    module_name = "_Builtin_stddef_max_align_t",
    system_module_map = "__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/clang/include/module.modulemap",
    tags = FIXTURE_TAGS,
)
