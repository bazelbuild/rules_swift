"""Linux standalone C/C++ configuration, independent of compiler extraction."""

load("@apple_support//toolchain:cc_toolchain.bzl", apple_support_cc_toolchain = "cc_toolchain")
load("@rules_cc//cc/toolchains:feature.bzl", "cc_feature")
load("@rules_cc//cc/toolchains/args:sysroot.bzl", "cc_sysroot")

def standalone_linux_cc_toolchain(*, name, tool_map, sysroot_version):
    """Defines the Linux C/C++ configuration in a dedicated package.

    Keeping the configuration outside the compiler repository allows Bazel to
    discover the compiler and selected sysroot dependencies concurrently.

    Args:
        name: Name of the toolchain implementation target.
        tool_map: Compiler repository's cc_tool_map target.
        sysroot_version: Ubuntu release used for the default Linux sysroot.
    """
    cc_sysroot(
        name = "linux_aarch64_sysroot_args",
        actions = [
            Label("@rules_cc//cc/toolchains/actions:link_actions"),
            Label("@rules_cc//cc/toolchains/actions:compile_actions"),
        ],
        args = ["--gcc-toolchain={sysroot}/usr"],
        data = [Label("@swift_ubuntu{}_arm64_sysroot//:root".format(sysroot_version))],
        sysroot = Label("@swift_ubuntu{}_arm64_sysroot//:root".format(sysroot_version)),
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    cc_feature(
        name = "linux_aarch64_sysroot",
        args = [":linux_aarch64_sysroot_args"],
        feature_name = "sysroot",
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    cc_sysroot(
        name = "linux_x86_64_sysroot_args",
        actions = [
            Label("@rules_cc//cc/toolchains/actions:link_actions"),
            Label("@rules_cc//cc/toolchains/actions:compile_actions"),
        ],
        args = ["--gcc-toolchain={sysroot}/usr"],
        data = [Label("@swift_ubuntu{}_amd64_sysroot//:root".format(sysroot_version))],
        sysroot = Label("@swift_ubuntu{}_amd64_sysroot//:root".format(sysroot_version)),
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    cc_feature(
        name = "linux_x86_64_sysroot",
        args = [":linux_x86_64_sysroot_args"],
        feature_name = "sysroot",
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    native.alias(
        name = "linux_sysroot",
        actual = select({
            Label("@platforms//cpu:aarch64"): ":linux_aarch64_sysroot",
            Label("@platforms//cpu:x86_64"): ":linux_x86_64_sysroot",
        }),
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    native.alias(
        name = "selected_linux_sysroot_feature",
        actual = select({
            Label("@rules_swift//swift/toolchains:linux_sysroot_feature_is_default"): ":linux_sysroot",
            "//conditions:default": Label("@rules_swift//swift/toolchains:linux_sysroot_feature"),
        }),
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    apple_support_cc_toolchain(
        name = name,
        module_map = None,
        supports_header_parsing = False,
        sysroot_feature = ":selected_linux_sysroot_feature",
        target = select({
            Label("@platforms//cpu:aarch64"): "aarch64-unknown-linux-gnu",
            Label("@platforms//cpu:x86_64"): "x86_64-unknown-linux-gnu",
        }),
        tool_map = tool_map,
    )
