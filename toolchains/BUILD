load("@apple_support//configs:platforms.bzl", "APPLE_PLATFORMS_CONSTRAINTS")

toolchain_type(
    name = "toolchain_type",
    visibility = ["//visibility:public"],
)

toolchain_type(
    name = "sdk_toolchain_type",
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
    toolchain_type = ":toolchain_type",
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
    toolchain_type = ":toolchain_type",
    visibility = ["//visibility:public"],
)

[
    toolchain(
        name = "xcode-sdk-toolchain-" + arch,
        exec_compatible_with = [
            "@platforms//os:macos",
        ],
        target_compatible_with = constraints,
        toolchain = "//swift/toolchains:xcode-sdk-toolchain",
        toolchain_type = ":sdk_toolchain_type",
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
        toolchain = "//swift/toolchains:xcode-toolchain",
        toolchain_type = ":toolchain_type",
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
    toolchain_type = ":toolchain_type",
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
    toolchain_type = ":toolchain_type",
    visibility = ["//visibility:public"],
)
