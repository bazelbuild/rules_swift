load("@rules_cc//cc/toolchains:feature.bzl", "cc_feature")
load("@rules_cc//cc/toolchains/args:sysroot.bzl", "cc_sysroot")

cc_sysroot(
    name = "linux_aarch64_sysroot_args",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
        "@rules_cc//cc/toolchains/actions:compile_actions",
    ],
    data = ["@swift_ubuntu22.04_aarch64_sysroot//:root"],
    sysroot = "@swift_ubuntu22.04_aarch64_sysroot//:root",
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
        "@rules_cc//cc/toolchains/actions:link_actions",
        "@rules_cc//cc/toolchains/actions:compile_actions",
    ],
    data = ["@swift_ubuntu22.04_sysroot//:root"],
    sysroot = "@swift_ubuntu22.04_sysroot//:root",
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

alias(
    name = "linux_sysroot",
    actual = select({
        "@platforms//cpu:aarch64": ":linux_aarch64_sysroot",
        "@platforms//cpu:x86_64": ":linux_x86_64_sysroot",
    }),
    tags = ["manual"],
    visibility = ["//visibility:private"],
)
