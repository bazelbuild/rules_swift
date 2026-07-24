load("@rules_swift//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("@rules_swift//swift/toolchains:swift_tools.bzl", "swift_tools")

_ANDROID_ARCHS = [
    "aarch64",
    "armv7",
    "x86_64",
]

_RESOURCE_DIRS = {
    arch: "{lib_dir}/swift_static-" + arch
    for arch in _ANDROID_ARCHS
}

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

[
    swift_toolchain(
        name = "swift_toolchain_" + arch,
        arch = arch,
        copts = [
            "-resource-dir",
            _RESOURCE_DIRS[arch],
            "-Xcc",
            "-I{clang_builtin_headers}",
        ],
        features = [
            "swift.lld_gc_workaround",
            "swift.module_map_no_private_headers",
            "swift.use_autolink_extract",
            "swift.use_module_wrap",
        ],
        linker_inputs = [":sdk_files"],
        # Swift defines linkopts for android in
        # `swift_static-{arch}/android/static-stdlib-args.lnk`, we add the ones
        # that matter here removing the ones that rules_android_ndk already
        # passes.
        linkopts = [
            _RESOURCE_DIRS[arch] + "/android/" + arch + "/swiftrt.o",
            "-L" + _RESOURCE_DIRS[arch] + "/android",
            "-llog",
            "-lswiftCore",
            # Swift Concurrency's global executor lives on libdispatch, but the
            # dependency comes from C++ objects inside libswift_Concurrency.a,
            # so it is never autolinked. Link it (and its BlocksRuntime)
            # explicitly from the same SDK directory; lld only extracts
            # referenced members, so this is free for binaries that don't use
            # concurrency.
            "-ldispatch",
            "-lBlocksRuntime",
            "-Wl,-export-dynamic",
            "-Wl,--exclude-libs,ALL",
            # TODO: Remove once https://github.com/bazelbuild/rules_android_ndk/commit/efc0c191796477c540e87e0f6bb5d88d6a58cc1f is in a release
            "-Wl,-z,max-page-size=16384",
        ],
        os = "android",
        parsed_version = "{swift_version}",
        sdkroot = "",  # Resolved in swift_toolchain.bzl
        swift_tools = ":tools",
        version_file = ".swift-version",
    )
    for arch in _ANDROID_ARCHS
]
