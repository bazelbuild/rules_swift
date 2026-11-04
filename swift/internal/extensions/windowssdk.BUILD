# buildifier: disable=bzl-visibility
load("@rules_cc//cc/private/toolchain:windows_cc_toolchain_config.bzl", "cc_toolchain_config")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_swift//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("@rules_swift//swift/toolchains:swift_tools.bzl", "swift_tools")

_REPO = "{repo_root}"

_SDK = _REPO + "/swift-windows-sdk/Windows.platform/Developer/SDKs/Windows.sdk"

_MSVC = _REPO + "/winsysroot/VC/Tools/MSVC/{msvc_version}"

_KITS = _REPO + "/winsysroot/Windows Kits/10"

_INCLUDES = [
    _MSVC + "/include",
    _KITS + "/Include/{sdk_version}/ucrt",
    _KITS + "/Include/{sdk_version}/um",
    _KITS + "/Include/{sdk_version}/shared",
    _KITS + "/Include/{sdk_version}/winrt",
]

# Bazel's cpu: (Windows' name for it, rules_cc's cpu)
_ARCHS = {
    "aarch64": ("arm64", "arm64_windows"),
    "x86_64": ("x64", "x64_windows"),
}

filegroup(
    name = "sdk_files",
    srcs = glob([
        "resource/**",
        "swift-windows-sdk/Windows.platform/**",
    ]),
)

filegroup(
    name = "msvc_files",
    srcs = glob(["winsysroot/**"]),
)

# The Swift runtime's DLLs, which a Windows executable needs beside it.
[
    filegroup(
        name = "runtime_" + cpu,
        srcs = glob(["swift-windows-sdk/runtime/" + cpu + "/*.dll"]),
        visibility = ["//visibility:public"],
    )
    for cpu in _ARCHS
]

swift_tools(
    name = "tools",
    additional_inputs = [
        ":msvc_files",
        ":sdk_files",
        "@{toolchain_repo}//:swift_sdk_compiler_inputs",
    ],
    swift_autolink_extract = "@{toolchain_repo}//:usr/bin/swift-autolink-extract",
    swift_driver = "@{toolchain_repo}//:usr/bin/swiftc",
    swift_symbolgraph_extract = "@{toolchain_repo}//:usr/bin/swift-symbolgraph-extract",
)

[
    swift_toolchain(
        name = "swift_toolchain_" + cpu,
        arch = cpu,
        copts = [
            "-resource-dir",
            _REPO + "/resource",
            "-visualc-tools-root",
            _MSVC,
            "-windows-sdk-root",
            _KITS,
            "-windows-sdk-version",
            "{sdk_version}",
        ],
        features = [
            "swift.module_map_no_private_headers",
            "swift.no_embed_debug_module",
        ],
        linker_inputs = [
            ":msvc_files",
            ":sdk_files",
        ],
        os = "windows",
        parsed_version = "{swift_version}",
        sdkroot = _SDK,
        swift_tools = ":tools",
        version_file = ".swift-version",
        xctest_version = "{swift_version}",
    )
    for cpu in _ARCHS
]

filegroup(
    name = "cc_files",
    srcs = [
        "bin/clang-cl",
        "bin/lld-link",
        "bin/llvm-lib",
        ":msvc_files",
        ":sdk_files",
        "@{toolchain_repo}//:swift_sdk_linker_inputs",
    ],
)

[
    cc_toolchain_config(
        name = "cc_toolchain_config_" + cpu,
        abi_libc_version = "local",
        abi_version = "local",
        archiver_flags = ["/MACHINE:" + machine.upper()],
        compiler = "clang-cl",
        cpu = rules_cc_cpu,
        cxx_builtin_include_directories = _INCLUDES + ["{clang_root}"],
        dbg_mode_debug_flag = "/DEBUG:FULL",
        default_compile_flags = ["--target=" + cpu + "-pc-windows-msvc"],
        default_link_flags = ["/MACHINE:" + machine.upper()],
        fastbuild_mode_debug_flag = "/DEBUG:FASTLINK",
        host_system_name = "local",
        msvc_cl_path = "bin/clang-cl",
        msvc_env_include = ";".join(_INCLUDES),
        msvc_env_lib = ";".join([
            _MSVC + "/lib/" + machine,
            _KITS + "/Lib/{sdk_version}/ucrt/" + machine,
            _KITS + "/Lib/{sdk_version}/um/" + machine,
        ]),
        msvc_env_path = "/usr/bin:/bin",
        msvc_env_tmp = "/tmp",
        msvc_lib_path = "bin/llvm-lib",
        msvc_link_path = "bin/lld-link",
        msvc_ml_path = "bin/clang-cl",
        supports_parse_showincludes = False,
        target_libc = "ucrt",
        target_system_name = cpu + "-unknown-windows-msvc",
        tool_paths = {
            "ar": "bin/llvm-lib",
            "cpp": "bin/clang-cl",
            "gcc": "bin/clang-cl",
            "gcov": "/bin/false",
            "ld": "bin/lld-link",
            "ml": "bin/clang-cl",
            "nm": "/bin/false",
            "objcopy": "/bin/false",
            "objdump": "/bin/false",
            "strip": "/bin/false",
        },
        toolchain_identifier = "swift_windows_sdk_" + cpu,
    )
    for cpu, (machine, rules_cc_cpu) in _ARCHS.items()
]

[
    cc_toolchain(
        name = "cc_toolchain_" + cpu,
        all_files = ":cc_files",
        ar_files = ":cc_files",
        compiler_files = ":cc_files",
        dwp_files = ":cc_files",
        linker_files = ":cc_files",
        objcopy_files = ":cc_files",
        strip_files = ":cc_files",
        supports_param_files = 1,
        toolchain_config = ":cc_toolchain_config_" + cpu,
    )
    for cpu in _ARCHS
]
