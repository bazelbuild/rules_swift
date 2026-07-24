load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//swift:swift.bzl", "swift_binary")
load("//swift:swift_library.bzl", "swift_library")
load("//swift:swift_test.bzl", "swift_test")
load("//test/rules:provider_test.bzl", "provider_test")

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
