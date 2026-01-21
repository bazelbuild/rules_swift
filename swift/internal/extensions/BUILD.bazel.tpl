load("@build_bazel_rules_swift//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("@build_bazel_rules_swift//swift/toolchains:swift_tools.bzl", "swift_tools")
load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:make_variable.bzl", "cc_make_variable")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")

package(default_visibility = ["//visibility:public"])

### Convenience target. Only useful for test / debug. ###
filegroup(
    name = "files",
    srcs = glob(
        include = ["**/*"],
        exclude = [
            "BUILD.bazel",
            "*.pkg",
        ],
    ),
)

### Tools ###
cc_tool(
    name = "ar",
    src = "usr/bin/llvm-ar",
    tags = ["manual"],
)

cc_tool(
    name = "clang",
    src = "usr/bin/clang",
    tags = ["manual"],
)

cc_tool(
    name = "clang++",
    src = "usr/bin/clang++",
    tags = ["manual"],
)

cc_tool_map(
    name = "all_tools",
    tags = ["manual"],
    tools = {
        "@rules_cc//cc/toolchains/actions:ar_actions": ":ar",
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:c_compile": ":clang",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":clang++",
        "@rules_cc//cc/toolchains/actions:link_actions": ":clang",
    },
)

### Make variables ###
# Used in _swift_toolchain_impl() in swift/toolchain/swift_toolchain.bzl
cc_make_variable(
    name = "variable_cc_target_triple",
    value = select({
        "@platforms//cpu:aarch64": "aarch64-none-none-elf",
        "@platforms//cpu:armv6-m": "armv6m-none-none-eabi",
        "@platforms//cpu:armv7": "armv7-none-none-eabi",
        "@platforms//cpu:armv7e-m": "armv7em-none-none-eabi",
        "@platforms//cpu:riscv32": "riscv32-none-none-eabi",
        "@platforms//cpu:riscv64": "riscv64-none-none-eabi",
        "@platforms//cpu:wasm32": "wasm32-unknown-none-wasm",
        "@platforms//cpu:wasm64": "wasm64-unknown-none-wasm",
        "@platforms//cpu:x86_32": "i686-unknown-none-elf",
        "@platforms//cpu:x86_64": "x86_64-unknown-none-elf",
    }),
    variable_name = "CC_TARGET_TRIPLE",
)

cc_args(
    name = "args_target",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "-target",
    ] + select({
        "@platforms//cpu:aarch64": ["aarch64-none-none-elf"],
        "@platforms//cpu:armv6-m": ["armv6m-none-none-eabi"],
        "@platforms//cpu:armv7": ["armv7-none-none-eabi"],
        "@platforms//cpu:armv7e-m": ["armv7em-none-none-eabi"],
        "@platforms//cpu:riscv32": ["riscv32-none-none-eabi"],
        "@platforms//cpu:riscv64": ["riscv64-none-none-eabi"],
        "@platforms//cpu:wasm32": ["wasm32-unknown-none-wasm"],
        "@platforms//cpu:wasm64": ["wasm64-unknown-none-wasm"],
        "@platforms//cpu:x86_32": ["i686-unknown-none-elf"],
        "@platforms//cpu:x86_64": ["x86_64-unknown-none-elf"],
    }),
)

cc_args(
    name = "args_nostdlib",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = ["-nostdlib"],
)

### Toolchains definition ###
cc_toolchain(
    name = "cc_toolchain_embedded",
    args = [
        ":args_nostdlib",
        ":args_target",
    ],
    compiler = "clang",
    enabled_features = [
        "@rules_cc//cc/toolchains/args/archiver_flags:feature",
        "@rules_cc//cc/toolchains/args/libraries_to_link:feature",
        "@rules_cc//cc/toolchains/args/link_flags:feature",
    ],
    make_variables = [
        ":variable_cc_target_triple",
    ],
    tool_map = "all_tools",
)

swift_tools(
    name = "tools",
    swift_driver = "usr/bin/swiftc",
    swift_autolink_extract = "usr/bin/swift-autolink-extract",
    swift_symbolgraph_extract = "usr/bin/swift-symbolgraph-extract",
    additional_linker_inputs = glob(["usr/lib/swift/**"]),
)

swift_toolchain(
    name = "swift_toolchain_embedded",
    arch = "arm64",
    copts = [
        # The current version of swift requires passing -mergeable-symbols to the front-end
        # to avoid duplicated symbols at link time in embedded mode. This is documented here:
        # https://github.com/swiftlang/swift-package-manager/issues/8648
        # Note that this is a workaround that got removed in the change below:
        # https://github.com/swiftlang/swift-package-manager/pull/9246
        # When the new version of the compiler is released, we should remove this.
        "-Xfrontend",
        "-mergeable-symbols",
    ],
    features = [
        "swift.enable_embedded",
        "swift.no_embed_debug_module",
        "swift.use_autolink_extract",
        "-swift.file_prefix_map",
    ],
    os = "none",
    swift_tools = "tools",
    version_file = ".swift-version",
)

swift_toolchain(
    name = "swift_toolchain_exec",
    arch = select({
        "@platforms//cpu:aarch64": "aarch64",
        "@platforms//cpu:x86_64": "x86_64",
    }),
    features = [
        "swift.no_embed_debug_module",
        "swift.use_autolink_extract",
        "-swift.file_prefix_map",
    ],
    os = select({
        "@platforms//os:linux": "linux",
        "@platforms//os:macos": "macos",
    }),
    swift_tools = "tools",
    version_file = ".swift-version",
)