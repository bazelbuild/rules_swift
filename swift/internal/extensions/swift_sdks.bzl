"""Repository rules for downloading and configuring Swift SDKs.

A "Swift SDK" is the artifact bundle published by swift.org for
cross-compiling Swift to platforms that the host toolchain cannot target by
itself (currently WebAssembly and Android); they are the bundles that
`swift sdk install` consumes.

Each repository created by these rules pairs one Swift SDK with one standalone
host toolchain repository (created by `standalone_toolchain`) and defines:

  * a `swift_toolchain` that compiles against the SDK's sysroot and Swift
    resource directory, and links against its static Swift runtime; and
  * a rules_cc `cc_toolchain` that drives the matching clang for the target
    (the host toolchain's clang for WebAssembly, the Android NDK's clang for
    Android), which `swift_binary`/`cc_*` rules use to link.

The `toolchain` declarations that register these for a given target platform
are generated into the toolchains hub repository; see `toolchains.bzl`.

Because the Swift module format is not stable across compiler versions, a
Swift SDK must come from exactly the same release as the host toolchain it is
paired with; the `swift` module extension enforces this by deriving both from
the same `swift.toolchain` tag.
"""

# BUILD file written into the Android NDK repository fetched alongside the
# Android Swift SDK. The prebuilt directory name varies by host
# ("darwin-x86_64", "linux-x86_64"), hence the wildcards.
ANDROID_NDK_BUILD_FILE_CONTENT = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "clang",
    srcs = glob(["toolchains/llvm/prebuilt/*/bin/clang"]),
)

filegroup(
    name = "llvm_ar",
    srcs = glob(["toolchains/llvm/prebuilt/*/bin/llvm-ar"]),
)

filegroup(
    name = "toolchain_files",
    srcs = glob([
        "toolchains/llvm/prebuilt/*/bin/*",
        "toolchains/llvm/prebuilt/*/lib/**",
        "toolchains/llvm/prebuilt/*/sysroot/**",
    ]),
)

# The shared C++ runtime that must be packaged into any Android application
# that contains Swift code.
filegroup(
    name = "libcxx_shared_aarch64",
    srcs = glob(["toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"]),
)

filegroup(
    name = "libcxx_shared_x86_64",
    srcs = glob(["toolchains/llvm/prebuilt/*/sysroot/usr/lib/x86_64-linux-android/libc++_shared.so"]),
)
"""

# Files in the host toolchain that compile actions need: the driver/frontend
# binaries, their libraries, and clang's builtin headers (used by the clang
# importer when the Swift SDK's resource directory does not bundle them).
_HOST_COMPILER_INPUTS = "swift_sdk_compiler_inputs"

# Files in the host toolchain that link actions driven by its clang need.
_HOST_LINKER_INPUTS = "swift_sdk_linker_inputs"

_CC_TOOLCHAIN_TEMPLATE = """
cc_tool(
    name = "clang",
    src = "{clang}",
    data = {clang_data},
    tags = ["manual"],
)

cc_tool(
    name = "ar",
    src = "{ar}",
    tags = ["manual"],
)

cc_tool_map(
    name = "cc_tools",
    tags = ["manual"],
    tools = {{
        "@rules_cc//cc/toolchains/actions:ar_actions": ":ar",
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:c_compile": ":clang",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:link_actions": ":clang",
    }},
)
"""

_CC_TOOLCHAIN_FOR_TARGET_TEMPLATE = """
cc_args(
    name = "cc_args_{suffix}",
    actions = [
        "@rules_cc//cc/toolchains/actions:compile_actions",
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = {args},
)

cc_args(
    name = "cc_link_args_{suffix}",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = {link_args},
)

cc_make_variable(
    name = "cc_target_triple_{suffix}",
    value = "{triple}",
    variable_name = "CC_TARGET_TRIPLE",
)

cc_toolchain(
    name = "cc_toolchain_{suffix}",
    args = [
        ":cc_args_{suffix}",
        ":cc_link_args_{suffix}",
    ],
    compiler = "clang",
    enabled_features = [
        "@rules_cc//cc/toolchains/args/archiver_flags:feature",
        "@rules_cc//cc/toolchains/args/libraries_to_link:feature",
        "@rules_cc//cc/toolchains/args/link_flags:feature",
    ],
    make_variables = [
        ":cc_target_triple_{suffix}",
    ],
    tool_map = ":cc_tools",
)
"""

_SWIFT_TOOLCHAIN_TEMPLATE = """
swift_toolchain(
    name = "swift_toolchain_{suffix}",
    arch = "{arch}",
    copts = {copts},
    features = {features},
    linker_inputs = {linker_inputs},
    linkopts = {linkopts},
    os = "{os}",
    parsed_version = "{swift_version}",
    sdkroot = "{sdkroot}",
    swift_tools = ":tools",
    version_file = ".swift-version",
)
"""

_BUILD_HEADER_TEMPLATE = """\
load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:make_variable.bzl", "cc_make_variable")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")
load("@rules_swift//swift/toolchains:swift_toolchain.bzl", "swift_toolchain")
load("@rules_swift//swift/toolchains:swift_tools.bzl", "swift_tools")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "sdk_files",
    srcs = glob(["{bundle_dir}/**"]),
)

swift_tools(
    name = "tools",
    swift_driver = "@{toolchain_repo}//:usr/bin/swiftc",
    swift_autolink_extract = "@{toolchain_repo}//:usr/bin/swift-autolink-extract",
    swift_symbolgraph_extract = "@{toolchain_repo}//:usr/bin/swift-symbolgraph-extract",
    additional_inputs = {compiler_inputs},
)
"""

def _execroot_relative_path(path):
    """Returns the execution-root-relative path for an external repository path.

    Args:
        path: An absolute `path` (or string) below the output base's
            `external` directory.

    Returns:
        The same path expressed relative to the execution root, suitable for
        baking into command line flags.
    """
    path_str = str(path)
    if "/external/" not in path_str:
        fail("Expected a path inside an external repository, got: " + path_str)
    return "external/" + path_str.rsplit("/external/", 1)[1]

def _build_list(items, indent = "    "):
    """Formats a list of strings as a multi-line BUILD file list literal."""
    if not items:
        return "[]"
    lines = ["["]
    for item in items:
        lines.append("{}    \"{}\",".format(indent, item))
    lines.append(indent + "]")
    return "\n".join(lines)

def _download_sdk_bundle(repository_ctx):
    """Downloads and extracts the Swift SDK artifact bundle for a repository.

    Returns:
        The name of the top-level `.artifactbundle` directory.
    """
    repository_ctx.download_and_extract(
        url = repository_ctx.attr.url,
        sha256 = repository_ctx.attr.sha256,
    )
    repository_ctx.file(".swift-version", repository_ctx.attr.swift_version)

    bundles = [
        entry.basename
        for entry in repository_ctx.path(".").readdir()
        if entry.basename.endswith(".artifactbundle")
    ]
    if len(bundles) != 1:
        fail(("Expected the archive at {} to contain exactly one " +
              ".artifactbundle directory, found: {}").format(
            repository_ctx.attr.url,
            bundles,
        ))
    return bundles[0]

def _common_attrs():
    return {
        "sha256": attr.string(
            doc = "The expected SHA-256 of the SDK artifact bundle.",
            mandatory = True,
        ),
        "swift_version": attr.string(
            doc = "The Swift release version the SDK belongs to.",
            mandatory = True,
        ),
        "toolchain_repo": attr.string(
            doc = """\
Name of the `standalone_toolchain` repository providing the host tools that
this SDK is paired with.
""",
            mandatory = True,
        ),
        "url": attr.string(
            doc = "The download URL of the SDK artifact bundle.",
            mandatory = True,
        ),
    }

def _swift_wasm_sdk_impl(repository_ctx):
    bundle_dir = _download_sdk_bundle(repository_ctx)
    toolchain_repo = repository_ctx.attr.toolchain_repo

    repo_root = "external/" + repository_ctx.name
    sdk_dir = "{}/{}/{}".format(
        repo_root,
        bundle_dir,
        "{0}/wasm32-unknown-wasip1".format(bundle_dir.removesuffix(".artifactbundle")),
    )
    if not repository_ctx.path(sdk_dir.removeprefix(repo_root + "/")).exists:
        fail("The WebAssembly Swift SDK bundle has an unexpected layout; " +
             "missing " + sdk_dir)
    wasi_sdk = sdk_dir + "/WASI.sdk"
    resource_dir = sdk_dir + "/swift.xctoolchain/usr/lib/swift_static"

    build_content = _BUILD_HEADER_TEMPLATE.format(
        bundle_dir = bundle_dir,
        compiler_inputs = _build_list([
            ":sdk_files",
            "@{}//:{}".format(toolchain_repo, _HOST_COMPILER_INPUTS),
        ]),
        toolchain_repo = toolchain_repo,
    )

    build_content += _SWIFT_TOOLCHAIN_TEMPLATE.format(
        arch = "wasm32",
        copts = _build_list([
            "-resource-dir",
            resource_dir,
        ]),
        features = _build_list([
            "swift.module_map_no_private_headers",
            "swift.no_embed_debug_module",
            # wasm-ld cannot alias a renamed entry point back to the symbol
            # that wasi-libc's startup code expects.
            "swift.no_entry_point_rename",
            "swift.use_autolink_extract",
            # The file prefix map would make the worker resolve the Xcode
            # developer directory on macOS hosts, which this toolchain does
            # not depend on.
            "-swift.file_prefix_map",
        ]),
        linker_inputs = _build_list([":sdk_files"]),
        # The runtime objects and libraries that `swiftc` would add when
        # linking a static executable for WASI; see
        # `swift_static/wasi/static-executable-args.lnk` in the SDK.
        linkopts = _build_list([
            "{}/wasi/wasm32/swiftrt.o".format(resource_dir),
            "-L{}/wasi".format(resource_dir),
            "-lc++",
            "-lc++abi",
            "-lswiftSwiftOnoneSupport",
            "-ldl",
            "-lm",
            "-lwasi-emulated-mman",
            "-lwasi-emulated-signal",
            "-lwasi-emulated-process-clocks",
        ]),
        os = "wasi",
        sdkroot = wasi_sdk,
        suffix = "wasm32",
        swift_version = repository_ctx.attr.swift_version,
    )

    build_content += _CC_TOOLCHAIN_TEMPLATE.format(
        ar = "@{}//:usr/bin/llvm-ar".format(toolchain_repo),
        clang = "@{}//:usr/bin/clang".format(toolchain_repo),
        clang_data = _build_list([
            ":sdk_files",
            "@{}//:{}".format(toolchain_repo, _HOST_LINKER_INPUTS),
        ]),
    )

    build_content += _CC_TOOLCHAIN_FOR_TARGET_TEMPLATE.format(
        args = _build_list([
            "--target=wasm32-unknown-wasip1",
            "--sysroot=" + wasi_sdk,
        ]),
        # The Swift SDK's clang resource directory provides the compiler
        # builtins (libclang_rt) for wasm32, which the host toolchain's own
        # resource directory does not include.
        link_args = _build_list([
            "-resource-dir",
            resource_dir + "/clang",
        ]),
        suffix = "wasm32",
        triple = "wasm32-unknown-wasip1",
    )

    repository_ctx.file("BUILD.bazel", build_content)

swift_wasm_sdk_repository = repository_rule(
    attrs = _common_attrs(),
    doc = """\
Downloads the WebAssembly Swift SDK artifact bundle and defines Swift and C++
toolchains that target `wasm32-unknown-wasip1` using a standalone host
toolchain's compiler.
""",
    implementation = _swift_wasm_sdk_impl,
)

# The architectures the Android Swift SDK provides resources for and that
# `@platforms//cpu` can express. (The SDK also supports armv7, which can be
# added on demand.)
ANDROID_ARCHS = ["aarch64", "x86_64"]

def _swift_android_sdk_impl(repository_ctx):
    bundle_dir = _download_sdk_bundle(repository_ctx)
    toolchain_repo = repository_ctx.attr.toolchain_repo
    ndk_repo = repository_ctx.attr.ndk_repo
    api_level = repository_ctx.attr.api_level

    repo_root = "external/" + repository_ctx.name
    sdk_dir_relative = bundle_dir + "/swift-android"
    if not repository_ctx.path(sdk_dir_relative + "/swift-sdk.json").exists:
        fail("The Android Swift SDK bundle has an unexpected layout; " +
             "missing {}/{}/swift-sdk.json".format(repo_root, sdk_dir_relative))
    lib_dir = "{}/{}/swift-resources/usr/lib".format(repo_root, sdk_dir_relative)

    # The NDK's sysroot is the SDK to compile against; the Swift SDK bundle
    # deliberately ships without one (its setup-android-sdk.sh script would
    # symlink in a locally installed NDK).
    ndk_root = repository_ctx.path(repository_ctx.attr.ndk_source_properties).dirname
    prebuilts = ndk_root.get_child("toolchains", "llvm", "prebuilt").readdir()
    if len(prebuilts) != 1:
        fail("Expected exactly one prebuilt toolchain in the Android NDK, " +
             "found: " + str(prebuilts))
    ndk_sysroot = _execroot_relative_path(prebuilts[0].get_child("sysroot"))

    # The Android Swift SDK's resource directories do not bundle clang's
    # builtin headers, so the clang importer must be pointed at the host
    # toolchain's copy (which matches the clang embedded in swiftc).
    host_usr = repository_ctx.path(repository_ctx.attr.host_swiftc).dirname.dirname
    clang_versions = host_usr.get_child("lib", "clang").readdir()
    if len(clang_versions) != 1:
        fail("Expected exactly one clang version directory in the host " +
             "toolchain, found: " + str(clang_versions))
    clang_builtin_headers = _execroot_relative_path(
        clang_versions[0].get_child("include"),
    )

    build_content = _BUILD_HEADER_TEMPLATE.format(
        bundle_dir = bundle_dir,
        compiler_inputs = _build_list([
            ":sdk_files",
            "@{}//:{}".format(toolchain_repo, _HOST_COMPILER_INPUTS),
            "@{}//:toolchain_files".format(ndk_repo),
        ]),
        toolchain_repo = toolchain_repo,
    )

    build_content += _CC_TOOLCHAIN_TEMPLATE.format(
        ar = "@{}//:llvm_ar".format(ndk_repo),
        clang = "@{}//:clang".format(ndk_repo),
        clang_data = _build_list([
            ":sdk_files",
            "@{}//:toolchain_files".format(ndk_repo),
        ]),
    )

    for arch in ANDROID_ARCHS:
        triple = "{}-unknown-linux-android{}".format(arch, api_level)
        resource_dir = "{}/swift_static-{}".format(lib_dir, arch)

        build_content += _SWIFT_TOOLCHAIN_TEMPLATE.format(
            arch = arch,
            copts = _build_list([
                "-resource-dir",
                resource_dir,
                "-Xcc",
                "-I" + clang_builtin_headers,
            ]),
            features = _build_list([
                "swift.lld_gc_workaround",
                "swift.module_map_no_private_headers",
                "swift.use_autolink_extract",
                "swift.use_module_wrap",
                # The file prefix map would make the worker resolve the Xcode
                # developer directory on macOS hosts, which this toolchain
                # does not depend on.
                "-swift.file_prefix_map",
            ]),
            linker_inputs = _build_list([":sdk_files"]),
            # The runtime objects and libraries that `swiftc` would add when
            # statically linking the stdlib for Android; see
            # `swift_static-{arch}/android/static-stdlib-args.lnk` in the SDK.
            # The 16 KiB max page size is required by Android 15+.
            linkopts = _build_list([
                "{}/android/{}/swiftrt.o".format(resource_dir, arch),
                "-L{}/android".format(resource_dir),
                "-ldl",
                "-llog",
                "-lm",
                "-lstdc++",
                "-Wl,--exclude-libs,ALL",
                "-Wl,-z,max-page-size=16384",
            ]),
            os = "android",
            sdkroot = ndk_sysroot,
            suffix = arch,
            swift_version = repository_ctx.attr.swift_version,
        )

        build_content += _CC_TOOLCHAIN_FOR_TARGET_TEMPLATE.format(
            args = _build_list(["--target=" + triple]),
            link_args = _build_list(["-Wl,-z,max-page-size=16384"]),
            suffix = arch,
            triple = triple,
        )

    repository_ctx.file("BUILD.bazel", build_content)

swift_android_sdk_repository = repository_rule(
    attrs = _common_attrs() | {
        "api_level": attr.int(
            doc = "The Android API level to target.",
            mandatory = True,
        ),
        "host_swiftc": attr.label(
            doc = """\
The host toolchain's `swiftc`, used to locate the clang builtin headers that
match the clang embedded in the Swift compiler.
""",
            mandatory = True,
        ),
        "ndk_repo": attr.string(
            doc = "Name of the repository containing the Android NDK.",
            mandatory = True,
        ),
        "ndk_source_properties": attr.label(
            doc = "The NDK repository's `source.properties` file (its directory is the NDK root).",
            mandatory = True,
        ),
    },
    doc = """\
Downloads the Android Swift SDK artifact bundle and defines Swift and C++
toolchains that target `{aarch64,x86_64}-unknown-linux-android` using a
standalone host toolchain's Swift compiler and the Android NDK's clang.
""",
    implementation = _swift_android_sdk_impl,
)
