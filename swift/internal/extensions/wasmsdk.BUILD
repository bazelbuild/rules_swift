load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:make_variable.bzl", "cc_make_variable")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")
load("@rules_swift//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("@rules_swift//swift/toolchains:swift_tools.bzl", "swift_tools")

_RESOURCE_DIR = "{sdk_dir}/swift.xctoolchain/usr/lib/swift_static"

_WASI_SDK = "{sdk_dir}/WASI.sdk"

filegroup(
    name = "sdk_files",
    srcs = glob(["{bundle_dir}/**"]),
)

swift_tools(
    name = "tools",
    additional_inputs = [
        ":sdk_files",
        "@{toolchain_repo}//:swift_sdk_compiler_inputs",
    ],
    swift_autolink_extract = "@{toolchain_repo}//:usr/bin/swift-autolink-extract",
    swift_driver = "@{toolchain_repo}//:usr/bin/swiftc",
    swift_symbolgraph_extract = "@{toolchain_repo}//:usr/bin/swift-symbolgraph-extract",
)

swift_toolchain(
    name = "swift_toolchain_wasm32",
    arch = "wasm32",
    copts = [
        "-resource-dir",
        _RESOURCE_DIR,{swift_thread_copts}
    ],
    features = [
        "swift.module_map_no_private_headers",
        "swift.no_embed_debug_module",
        # wasm-ld cannot alias a renamed entry point back to the symbol
        # that wasi-libc's startup code expects.
        "swift.no_entry_point_rename",
        "swift.use_autolink_extract",
    ],
    linker_inputs = [":sdk_files"],
    # The runtime objects and libraries that `swiftc` would add when linking a
    # static executable for WASI; see `swift_static/wasi/static-executable-args.lnk`
    # in the SDK.
    linkopts = [
        _RESOURCE_DIR + "/wasi/wasm32/swiftrt.o",
        "-L" + _RESOURCE_DIR + "/wasi",
        "-lc++",
        "-lc++abi",
        "-lswiftSwiftOnoneSupport",
        "-ldl",
        "-lm",
        "-lwasi-emulated-mman",
        "-lwasi-emulated-signal",
        "-lwasi-emulated-process-clocks",
        # The Swift driver always passes these bases to wasm-ld.
        # `--table-base=4096` in particular is required: without it, optimized
        # (`-O`) generic-metadata instantiation reads out of bounds at runtime
        # (`-Onone` happens to tolerate the default).
        "-Wl,--global-base=4096",
        "-Wl,--table-base=4096",{swift_thread_linkopts}
    ],
    os = "wasi",
    parsed_version = "{swift_version}",
    sdkroot = _WASI_SDK,
    swift_tools = ":tools",
    version_file = ".swift-version",
)

cc_tool(
    name = "clang",
    src = "@{toolchain_repo}//:usr/bin/clang",
    data = [
        ":sdk_files",
        "@{toolchain_repo}//:swift_sdk_linker_inputs",
    ],
    tags = ["manual"],
)

cc_tool(
    name = "ar",
    src = "@{toolchain_repo}//:usr/bin/llvm-ar",
    tags = ["manual"],
)

cc_tool_map(
    name = "cc_tools",
    tags = ["manual"],
    tools = {
        "@rules_cc//cc/toolchains/actions:ar_actions": ":ar",
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:c_compile": ":clang",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:link_actions": ":clang",
    },
)

cc_args(
    name = "cc_args_wasm32",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "--target={target_triple}",
        "--sysroot=" + _WASI_SDK,{cc_thread_compile_args}
    ],
)

cc_args(
    name = "cc_link_args_wasm32",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    # The Swift SDK's clang resource directory provides the compiler builtins
    # (libclang_rt) for wasm32, which the host toolchain's own resource
    # directory does not include.
    args = [
        "-resource-dir",
        _RESOURCE_DIR + "/clang",{cc_thread_link_args}
    ],
)

cc_make_variable(
    name = "cc_target_triple_wasm32",
    value = "{target_triple}",
    variable_name = "CC_TARGET_TRIPLE",
)

cc_toolchain(
    name = "cc_toolchain_wasm32",
    args = [
        ":cc_args_wasm32",
        ":cc_link_args_wasm32",
    ],
    compiler = "clang",
    enabled_features = [
        "@rules_cc//cc/toolchains/args/archiver_flags:feature",
        "@rules_cc//cc/toolchains/args/libraries_to_link:feature",
        "@rules_cc//cc/toolchains/args/link_flags:feature",
        # Needed so `swift_binary(linkshared = True)` links a shared library
        # (passes `-shared` for the dynamic_library link action).
        "@rules_cc//cc/toolchains/args/shared_flag:feature",
    ],
    make_variables = [":cc_target_triple_wasm32"],
    tool_map = ":cc_tools",
)
