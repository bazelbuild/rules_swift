load("@rules_cc//cc:cc_test.bzl", "cc_test")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load("//test:transitions.bzl", "transition_test")
load("//test/rules:provider_test.bzl", "provider_test")

cc_test(
    name = "sysroot_cc_test",
    srcs = [
        "sysroot.c",
        "sysroot.h",
        "sysroot_test.cc",
    ],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:linux"],
)

[
    transition_test(
        name = "linux_ubuntu{}_cc_test".format(version),
        extra_toolchains = [
            "@swift_toolchain//:cc_toolchain_exec_ubuntu{}".format(version),
            "@swift_toolchain//:cc_toolchain_exec_ubuntu{}-aarch64".format(version),
        ],
        target = ":sysroot_cc_test",
        target_compatible_with = [
            "@platforms//os:linux",
            "@platforms_contrib//os/linux/libc/glibc:at_least_{}_available".format(glibc),
        ],
    )
    for version, glibc in [
        ("22.04", "2.35"),
        ("24.04", "2.39"),
    ]
]

swift_library(
    name = "foundation_library",
    srcs = ["FoundationLibrary.swift"],
    module_name = "FoundationLibrary",
)

provider_test(
    name = "foundation_library_does_not_propagate_runtime_test",
    expected_files = [
        "-libFoundation.so",
        "-libswiftCore.so",
        "*",
    ],
    field = "linking_context.linker_inputs.libraries.dynamic_library!",
    provider = "CcInfo",
    target_under_test = ":foundation_library",
)

swift_binary(
    name = "uses_foundation",
    srcs = ["main.swift"],
    tags = ["manual"],
    deps = [":foundation_library"],
)

swift_binary(
    name = "uses_dynamic_foundation",
    srcs = ["main.swift"],
    features = ["-swift.static_stdlib"],
    tags = ["manual"],
    deps = [":foundation_library"],
)

# A dynamically linked binary's runfiles must carry the shared Swift runtime
# libraries its RUNPATH points at, or it only runs from the output tree it was
# built in (and fails to load them under remote execution, for example).
provider_test(
    name = "uses_dynamic_foundation_runfiles_test",
    expected_files = [
        "libFoundation.so",
        "libswiftCore.so",
        "*",
    ],
    field = "default_runfiles.files",
    provider = "DefaultInfo",
    target_compatible_with = ["@platforms//os:linux"],
    target_under_test = ":uses_dynamic_foundation",
)

swift_binary(
    name = "uses_foundation_shared",
    srcs = ["FoundationLibrary.swift"],
    linkshared = True,
    module_name = "FoundationSharedLibrary",
    tags = ["manual"],
)

swift_test(
    name = "foundation_library_test",
    srcs = ["FoundationLibraryTests.swift"],
    deps = [":foundation_library"],
)

swift_test(
    name = "foundation_library_dynamic_test",
    srcs = ["FoundationLibraryTests.swift"],
    features = ["-swift.static_stdlib"],
    target_compatible_with = ["@platforms//os:linux"],
    deps = [":foundation_library"],
)

provider_test(
    name = "foundation_library_dynamic_test_runfiles_test",
    expected_files = [
        "libswiftCore.so",
        "*",
    ],
    field = "default_runfiles.files",
    provider = "DefaultInfo",
    target_compatible_with = ["@platforms//os:linux"],
    target_under_test = ":foundation_library_dynamic_test",
)

sh_test(
    name = "linux_dynamic_stdlib_test",
    srcs = ["linux_dynamic_stdlib_test.sh"],
    args = [
        "$(rootpath :uses_dynamic_foundation)",
        "$(rootpath @swift_toolchain_ubuntu22.04//:usr/bin/llvm-objdump)",
    ],
    data = [
        ":uses_dynamic_foundation",
        "@swift_toolchain_ubuntu22.04//:usr/bin/llvm-objdump",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
)

sh_test(
    name = "linux_linkshared_dynamic_stdlib_test",
    srcs = ["linux_linkshared_dynamic_stdlib_test.sh"],
    args = [
        "$(rootpath :uses_foundation_shared)",
        "$(rootpath @swift_toolchain_ubuntu22.04//:usr/bin/llvm-objdump)",
    ],
    data = [
        ":uses_foundation_shared",
        "@swift_toolchain_ubuntu22.04//:usr/bin/llvm-objdump",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
)

sh_test(
    name = "_linux_non_hermetic_dynamic_stdlib_test",
    srcs = ["linux_non_hermetic_dynamic_stdlib_test.sh"],
    args = [
        "$(rootpath :uses_dynamic_foundation)",
        "--execute",
    ],
    data = [":uses_dynamic_foundation"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:linux"],
)

sh_test(
    name = "_linux_non_hermetic_linkshared_dynamic_stdlib_test",
    srcs = ["linux_non_hermetic_dynamic_stdlib_test.sh"],
    args = ["$(rootpath :uses_foundation_shared)"],
    data = [":uses_foundation_shared"],
    tags = ["manual"],
    target_compatible_with = ["@platforms//os:linux"],
)

# These wrappers select the host Swift toolchains automatically. Keep them
# manual so hermetic //... builds do not select a host toolchain.
transition_test(
    name = "linux_non_hermetic_dynamic_stdlib_test",
    args = [
        "test/linux_static_stdlib/uses_dynamic_foundation",
        "--execute",
    ],
    extra_toolchains = [
        "//swift/toolchains:linux-swift-toolchain_aarch64",
        "//swift/toolchains:linux-swift-toolchain_x86_64",
    ],
    tags = ["manual"],
    target = ":_linux_non_hermetic_dynamic_stdlib_test",
    target_compatible_with = ["@platforms//os:linux"],
)

transition_test(
    name = "linux_non_hermetic_linkshared_dynamic_stdlib_test",
    args = ["test/linux_static_stdlib/libuses_foundation_shared.so"],
    extra_toolchains = [
        "//swift/toolchains:linux-swift-toolchain_aarch64",
        "//swift/toolchains:linux-swift-toolchain_x86_64",
    ],
    tags = ["manual"],
    target = ":_linux_non_hermetic_linkshared_dynamic_stdlib_test",
    target_compatible_with = ["@platforms//os:linux"],
)

sh_test(
    name = "linux_static_stdlib_test",
    srcs = ["linux_static_stdlib_test.sh"],
    args = [
        "$(rootpath :uses_foundation)",
        "$(rootpath @swift_toolchain_ubuntu22.04//:usr/bin/llvm-objdump)",
    ],
    data = [
        ":uses_foundation",
        "@swift_toolchain_ubuntu22.04//:usr/bin/llvm-objdump",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
)

transition_test(
    name = "linux_ubuntu22.04_foundation_test",
    extra_toolchains = [
        "@swift_toolchain//:cc_toolchain_exec_ubuntu22.04",
        "@swift_toolchain//:cc_toolchain_exec_ubuntu22.04-aarch64",
        "@swift_toolchain//:swift_toolchain_exec_ubuntu22.04",
        "@swift_toolchain//:swift_toolchain_exec_ubuntu22.04-aarch64",
    ],
    target = ":foundation_library_test",
    target_compatible_with = ["@platforms//os:linux"],
)

transition_test(
    name = "linux_ubuntu24.04_foundation_test",
    extra_toolchains = [
        "@swift_toolchain//:cc_toolchain_exec_ubuntu24.04",
        "@swift_toolchain//:cc_toolchain_exec_ubuntu24.04-aarch64",
        "@swift_toolchain//:swift_toolchain_exec_ubuntu24.04",
        "@swift_toolchain//:swift_toolchain_exec_ubuntu24.04-aarch64",
    ],
    # Requires glibc version from 24.04+
    tags = ["manual"],
    target = ":foundation_library_test",
    target_compatible_with = ["@platforms//os:linux"],
)
