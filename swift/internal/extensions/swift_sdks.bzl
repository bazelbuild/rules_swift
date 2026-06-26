"""Shared building blocks for Swift SDK repository rules, plus the Android SDK
repository rule.

A "Swift SDK" is an artifact bundle published by swift.org for cross-compiling
Swift to a platform the host toolchain cannot target by itself (the bundles that
`swift sdk install` consumes). The `android_sdk` extension defines a repository
rule that downloads such a bundle and generates a `swift_toolchain` targeting
`{aarch64,x86_64}-unknown-linux-android`; this module holds the helpers and
BUILD-file template it uses. C/C++ compilation and linking go through a
separately registered Android cc toolchain (e.g. `@androidndk//:all`), which also
provides the sysroot the Swift toolchain reads.

Because the Swift module format is not stable across compiler versions, a Swift
SDK must come from exactly the same release as the host toolchain it is paired
with; the `swift` module extension enforces this by deriving both from the same
`swift.toolchain` tag.
"""

# Files in the host toolchain that compile actions need: the driver/frontend
# binaries, their libraries, and clang's builtin headers (used by the clang
# importer when the Swift SDK's resource directory does not bundle them).
_HOST_COMPILER_INPUTS = "swift_sdk_compiler_inputs"

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

    # buildifier: disable=external-path
    if "/external/" not in path_str:
        fail("Expected a path inside an external repository, got: " + path_str)

    # buildifier: disable=external-path
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

# The architectures the Android Swift SDK provides resources for and that
# `@platforms//cpu` can express. (The SDK also supports armv7, which can be
# added on demand.)
ANDROID_ARCHS = ["aarch64", "x86_64"]

def _swift_android_sdk_impl(repository_ctx):
    bundle_dir = _download_sdk_bundle(repository_ctx)
    toolchain_repo = repository_ctx.attr.toolchain_repo

    repo_root = "external/" + repository_ctx.name
    sdk_dir_relative = bundle_dir + "/swift-android"
    if not repository_ctx.path(sdk_dir_relative + "/swift-sdk.json").exists:
        fail("The Android Swift SDK bundle has an unexpected layout; " +
             "missing {}/{}/swift-sdk.json".format(repo_root, sdk_dir_relative))
    lib_dir = "{}/{}/swift-resources/usr/lib".format(repo_root, sdk_dir_relative)

    # The Android Swift SDK's resource directories do not bundle clang's
    # builtin headers, so the clang importer must be pointed at the host
    # toolchain's copy (which matches the clang embedded in swiftc).
    paired_usr = repository_ctx.path(repository_ctx.attr.paired_swiftc).dirname.dirname
    clang_versions = paired_usr.get_child("lib", "clang").readdir()
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
        ]),
        toolchain_repo = toolchain_repo,
    )

    for arch in ANDROID_ARCHS:
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
            ]),
            linker_inputs = _build_list([":sdk_files"]),
            # The Swift runtime objects/libraries from the SDK's
            # `swift_static-{arch}/android/static-stdlib-args.lnk`. We drop that
            # file's `-Wl,--exclude-libs,ALL` (it would demote a depended-on
            # `swift_library`'s `@_cdecl` JNI exports to local) and add the 16 KiB
            # max page size required by Android 15+.
            linkopts = _build_list([
                "{}/android/{}/swiftrt.o".format(resource_dir, arch),
                "-L{}/android".format(resource_dir),
                "-ldl",
                "-llog",
                # libc++ as the shared `libc++_shared.so` (the SDK's intended
                # linkage). The Android cc toolchain links libc++ statically by
                # default (https://github.com/bazelbuild/rules_android_ndk/issues/93),
                # which the NDK discourages for a library that may share a process
                # with other `.so`s; `-lstdc++` overrides that to the shared
                # runtime, which must then be packaged into the APK (see
                # `select_android_runtime_lib`).
                "-lstdc++",
                "-Wl,-z,max-page-size=16384",
            ]),
            os = "android",
            # Empty: the toolchain reads the sysroot from the resolved Android
            # C++ cc toolchain (e.g. `@androidndk//:all`) at analysis time.
            sdkroot = "",
            suffix = arch,
            swift_version = repository_ctx.attr.swift_version,
        )

    repository_ctx.file("BUILD.bazel", build_content)

swift_android_sdk_repository = repository_rule(
    attrs = _common_attrs() | {
        "paired_swiftc": attr.label(
            doc = """\
The `swiftc` of the standalone toolchain this SDK is paired with, used to locate
the clang builtin headers that match the clang embedded in the Swift compiler.
""",
            mandatory = True,
        ),
    },
    doc = """\
Downloads the Android Swift SDK artifact bundle and defines Swift toolchains that
target Android.
""",
    implementation = _swift_android_sdk_impl,
)
