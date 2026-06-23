load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:make_variable.bzl", "cc_make_variable")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")
load(
    "//swift/toolchains:swift_toolchain.bzl",
    "swift_toolchain",
)

exports_files(["fake_tool.sh"])

platform(
    name = "linux_musl_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        "//swift/toolchains:static_linux",
    ],
)

swift_toolchain(
    name = "_toolchain_macos_arm64_with_sdkroot",
    arch = "arm64",
    os = "macos",
    parsed_version = "6.3",
    root = ".",
    sdkroot = "testpath",
    version_file = ".swift_version",
)

toolchain(
    name = "toolchain_macos_arm64_with_sdkroot",
    toolchain = ":_toolchain_macos_arm64_with_sdkroot",
    toolchain_type = "//toolchains:toolchain_type",
)

cc_tool(
    name = "fake_clang",
    src = "fake_tool.sh",
    tags = ["manual"],
)

cc_tool_map(
    name = "cc_tools_static_linux_x86_64",
    tags = ["manual"],
    tools = {
        "@rules_cc//cc/toolchains/actions:ar_actions": ":fake_clang",
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":fake_clang",
        "@rules_cc//cc/toolchains/actions:c_compile": ":fake_clang",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":fake_clang",
        "@rules_cc//cc/toolchains/actions:link_actions": ":fake_clang",
    },
)

cc_args(
    name = "cc_args_static_linux_x86_64",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "--target=x86_64-swift-linux-musl",
        "--sysroot=static-sdk-root",
    ],
)

cc_args(
    name = "cc_link_args_static_linux_x86_64",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "-lc++",
    ],
)

cc_make_variable(
    name = "cc_target_triple_static_linux_x86_64",
    value = "x86_64-swift-linux-musl",
    variable_name = "CC_TARGET_TRIPLE",
)

cc_toolchain(
    name = "_cc_toolchain_static_linux_x86_64",
    args = [
        ":cc_args_static_linux_x86_64",
        ":cc_link_args_static_linux_x86_64",
    ],
    compiler = "clang",
    enabled_features = [
        "@rules_cc//cc/toolchains/args/archiver_flags:feature",
        "@rules_cc//cc/toolchains/args/libraries_to_link:feature",
        "@rules_cc//cc/toolchains/args/link_flags:feature",
    ],
    make_variables = [
        ":cc_target_triple_static_linux_x86_64",
    ],
    tool_map = ":cc_tools_static_linux_x86_64",
)

toolchain(
    name = "cc_toolchain_static_linux_x86_64",
    toolchain = ":_cc_toolchain_static_linux_x86_64",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

cc_binary(
    name = "static_linux_cc_uses_libcxx",
    srcs = ["static_linux_cc_uses_libcxx.cc"],
    tags = ["manual"],
    visibility = ["//test:__pkg__"],
)

swift_toolchain(
    name = "_toolchain_static_linux_x86_64",
    arch = "x86_64",
    copts = [
        "-resource-dir",
        "static-resource-root",
    ],
    features = [
        "swift.use_autolink_extract",
    ],
    linker_inputs = [":fake_tool.sh"],
    linkopts = ["-static"],
    os = "linux",
    parsed_version = "6.3.2",
    root = ".",
    sdkroot = "static-sdk-root",
    version_file = ".swift_version",
)

toolchain(
    name = "toolchain_static_linux_x86_64",
    toolchain = ":_toolchain_static_linux_x86_64",
    toolchain_type = "//toolchains:toolchain_type",
)
