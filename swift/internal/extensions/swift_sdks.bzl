"""Shared building blocks for Swift SDK repository rules.

A "Swift SDK" is an artifact bundle published by swift.org for cross-compiling
Swift to a platform the host toolchain cannot target by itself (the bundles that
`swift sdk install` consumes). The per-platform extensions (`android_sdk`,
`wasm_sdk`, `static_linux_sdk`) define repository rules that download such a
bundle and generate a `swift_toolchain` for the target; this module holds the
helpers and BUILD-file templates they share. Android's C/C++ compilation and
linking go through a separately registered Android cc toolchain (e.g.
`@androidndk//:all`), while the WebAssembly and Static Linux repositories also
generate rules_cc `cc_toolchain` targets that drive the paired toolchain's clang.

Because the Swift module format is not stable across compiler versions, a Swift
SDK must come from exactly the same release as the host toolchain it is paired
with; the `swift` module extension enforces this by deriving both from the same
`swift.toolchain` tag.
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

# Some SDK repositories also generate a rules_cc cc_toolchain, so their BUILD
# header needs the rules_cc toolchain loads.
_CC_BUILD_HEADER_TEMPLATE = """\
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
        # Needed so `swift_binary(linkshared = True)` links a shared library
        # (passes `-shared` for the dynamic_library link action).
        "@rules_cc//cc/toolchains/args/shared_flag:feature",
    ],
    make_variables = [
        ":cc_target_triple_{suffix}",
    ],
    tool_map = ":cc_tools",
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

def _relative_metadata_path(value, field, triple):
    """Validates a path read from SDK metadata."""
    if type(value) != "string" or not value:
        fail("Expected `{}` for `{}` in swift-sdk.json to be a non-empty string.".format(
            field,
            triple,
        ))
    if value.startswith("/") or ".." in value.split("/"):
        fail("Expected `{}` for `{}` in swift-sdk.json to be a relative path below the SDK directory, got `{}`.".format(
            field,
            triple,
            value,
        ))
    return value

def _static_linux_resource_path(target_settings, triple):
    return _relative_metadata_path(
        target_settings.get("swiftStaticResourcesPath"),
        "swiftStaticResourcesPath",
        triple,
    )

def static_linux_linkopts_from_args(
        *,
        arch,
        linux_static_dir,
        args,
        include_swiftrt = True):
    """Returns linkopts using a Static Linux `static-executable-args.lnk` file.

    Args:
        arch: The target architecture.
        linux_static_dir: The execroot-relative `linux-static` resource
            directory.
        args: The parsed non-empty lines from `static-executable-args.lnk`.
        include_swiftrt: If True, add the `swiftrt.o` path used by the current
            Static Linux SDK layout.

    Returns:
        Linkopts suitable for a C/C++ linker action.
    """
    linkopts = []
    if include_swiftrt:
        linkopts.append("{}/{}/swiftrt.o".format(linux_static_dir, arch))
    linkopts.append("-L{}".format(linux_static_dir))
    return linkopts + args

def _static_linux_linkopts_from_sdk(
        repository_ctx,
        *,
        arch,
        linux_static_dir,
        linux_static_dir_relative,
        repo_root):
    swiftrt_relative = "{}/{}/swiftrt.o".format(linux_static_dir_relative, arch)
    args_relative = linux_static_dir_relative + "/static-executable-args.lnk"
    if not repository_ctx.path(args_relative).exists:
        fail("The Static Linux Swift SDK bundle has an unexpected layout; " +
             "missing {}/{}".format(repo_root, args_relative))

    args = []
    for line in repository_ctx.read(args_relative).split("\n"):
        arg = line.strip()
        if arg:
            args.append(arg)

    return static_linux_linkopts_from_args(
        arch = arch,
        args = args,
        include_swiftrt = repository_ctx.path(swiftrt_relative).exists,
        linux_static_dir = linux_static_dir,
    )

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

# Mirrored from https://github.com/bazelbuild/rules_android_ndk/blob/27b38742eade7e8000b9ed0f320c9f277a0e89d1/target_systems.bzl.tpl
# Swift doesn't support any other ones
ANDROID_ARCHS = [
    "aarch64",
    "armv7",
    "x86_64",
]

def _swift_android_sdk_impl(repository_ctx):
    bundle_dir = _download_sdk_bundle(repository_ctx)
    toolchain_repo = repository_ctx.attr.toolchain_repo

    repo_root = "external/" + repository_ctx.name
    sdk_dir_relative = bundle_dir + "/swift-android"
    if not repository_ctx.path(sdk_dir_relative + "/swift-sdk.json").exists:
        fail("The Android Swift SDK bundle has an unexpected layout; " +
             "missing {}/{}/swift-sdk.json".format(repo_root, sdk_dir_relative))
    lib_dir = "{}/{}/swift-resources/usr/lib".format(repo_root, sdk_dir_relative)

    # The clang headers are provided by the Swift toolchain, not the Android SDK bundle
    paired_usr = repository_ctx.path(repository_ctx.attr.paired_swiftc).dirname.dirname
    clang_versions = paired_usr.get_child("lib", "clang").readdir()
    if len(clang_versions) != 1:
        fail("Expected exactly one clang version directory in the host " +
             "toolchain, found: " + str(clang_versions))
    clang_builtin_headers = _execroot_relative_path(clang_versions[0].get_child("include"))

    build_content = _BUILD_HEADER_TEMPLATE.format(
        bundle_dir = bundle_dir,
        compiler_inputs = _build_list([
            ":sdk_files",
            "@{}//:swift_sdk_compiler_inputs".format(toolchain_repo),
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
            # Swift defines linkopts for android in
            # `swift_static-{arch}/android/static-stdlib-args.lnk`, we add the
            # ones that matter here removing the ones that rules_android_ndk
            # already passes.
            linkopts = _build_list([
                "{}/android/{}/swiftrt.o".format(resource_dir, arch),
                "-L{}/android".format(resource_dir),
                "-llog",
                "-lswiftCore",
                # Swift Concurrency's global executor lives on libdispatch,
                # but the dependency comes from C++ objects inside
                # libswift_Concurrency.a, so it is never autolinked. Link it
                # (and its BlocksRuntime) explicitly from the same SDK
                # directory; lld only extracts referenced members, so this is
                # free for binaries that don't use concurrency.
                "-ldispatch",
                "-lBlocksRuntime",
                "-Wl,-export-dynamic",
                "-Wl,--exclude-libs,ALL",
                # TODO: Remove once https://github.com/bazelbuild/rules_android_ndk/commit/efc0c191796477c540e87e0f6bb5d88d6a58cc1f is in a release
                "-Wl,-z,max-page-size=16384",
            ]),
            os = "android",
            sdkroot = "",  # Resolved in swift_toolchain.bzl
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

    build_content = _CC_BUILD_HEADER_TEMPLATE.format(
        bundle_dir = bundle_dir,
        compiler_inputs = _build_list([
            ":sdk_files",
            "@{}//:swift_sdk_compiler_inputs".format(toolchain_repo),
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
            # The Swift driver always passes these bases to wasm-ld.
            # `--table-base=4096` in particular is required: without it,
            # optimized (`-O`) generic-metadata instantiation reads out of
            # bounds at runtime (`-Onone` happens to tolerate the default).
            "-Wl,--global-base=4096",
            "-Wl,--table-base=4096",
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
            "@{}//:swift_sdk_linker_inputs".format(toolchain_repo),
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

# The architectures the Static Linux Swift SDK provides resources for and that
# `@platforms//cpu` can express.
STATIC_LINUX_ARCHS = ["aarch64", "x86_64"]

def _swift_static_linux_sdk_impl(repository_ctx):
    bundle_dir = _download_sdk_bundle(repository_ctx)
    toolchain_repo = repository_ctx.attr.toolchain_repo

    repo_root = "external/" + repository_ctx.name
    sdk_dir_relative = "{}/{}/swift-linux-musl".format(
        bundle_dir,
        bundle_dir.removesuffix(".artifactbundle"),
    )
    if not repository_ctx.path(sdk_dir_relative + "/swift-sdk.json").exists:
        fail("The Static Linux Swift SDK bundle has an unexpected layout; " +
             "missing {}/{}/swift-sdk.json".format(repo_root, sdk_dir_relative))
    swift_sdk_metadata = json.decode(
        repository_ctx.read(sdk_dir_relative + "/swift-sdk.json"),
    )
    target_triples = swift_sdk_metadata.get("targetTriples")
    if type(target_triples) != "dict":
        fail("The Static Linux Swift SDK bundle has an unexpected layout; " +
             "swift-sdk.json is missing `targetTriples`.")

    build_content = _CC_BUILD_HEADER_TEMPLATE.format(
        bundle_dir = bundle_dir,
        compiler_inputs = _build_list([
            ":sdk_files",
            "@{}//:swift_sdk_compiler_inputs".format(toolchain_repo),
        ]),
        toolchain_repo = toolchain_repo,
    )

    build_content += _CC_TOOLCHAIN_TEMPLATE.format(
        ar = "@{}//:usr/bin/llvm-ar".format(toolchain_repo),
        clang = "@{}//:usr/bin/clang".format(toolchain_repo),
        clang_data = _build_list([
            ":sdk_files",
            "@{}//:swift_sdk_linker_inputs".format(toolchain_repo),
        ]),
    )

    for arch in STATIC_LINUX_ARCHS:
        triple = "{}-swift-linux-musl".format(arch)
        suffix = "static_linux_{}".format(arch)
        target_settings = target_triples.get(triple)
        if type(target_settings) != "dict":
            fail("The Static Linux Swift SDK bundle does not define target triple `{}`.".format(
                triple,
            ))
        sdkroot_relative = "{}/{}".format(
            sdk_dir_relative,
            _relative_metadata_path(
                target_settings.get("sdkRootPath"),
                "sdkRootPath",
                triple,
            ),
        )
        resource_dir_relative = "{}/{}".format(
            sdk_dir_relative,
            _static_linux_resource_path(target_settings, triple),
        )
        sdkroot = "{}/{}".format(repo_root, sdkroot_relative)
        if not repository_ctx.path(sdkroot_relative).exists:
            fail("The Static Linux Swift SDK bundle has an unexpected layout; " +
                 "missing " + sdkroot)
        resource_dir = "{}/{}".format(repo_root, resource_dir_relative)
        if not repository_ctx.path(resource_dir_relative).exists:
            fail("The Static Linux Swift SDK bundle has an unexpected layout; " +
                 "missing " + resource_dir)
        linux_static_dir_relative = resource_dir_relative + "/linux-static"
        linux_static_dir = resource_dir + "/linux-static"

        build_content += _SWIFT_TOOLCHAIN_TEMPLATE.format(
            arch = arch,
            copts = _build_list([
                "-resource-dir",
                resource_dir,
            ]),
            features = _build_list([
                "swift.module_map_no_private_headers",
                "swift.no_embed_debug_module",
                "swift.use_autolink_extract",
            ]),
            linker_inputs = _build_list([":sdk_files"]),
            linkopts = _build_list(_static_linux_linkopts_from_sdk(
                repository_ctx,
                arch = arch,
                linux_static_dir = linux_static_dir,
                linux_static_dir_relative = linux_static_dir_relative,
                repo_root = repo_root,
            )),
            os = "linux",
            sdkroot = sdkroot,
            suffix = suffix,
            swift_version = repository_ctx.attr.swift_version,
        )

        build_content += _CC_TOOLCHAIN_FOR_TARGET_TEMPLATE.format(
            args = _build_list([
                "--target=" + triple,
                "--sysroot=" + sdkroot,
                "-resource-dir",
                resource_dir + "/clang",
            ]),
            link_args = _build_list([
                "-fuse-ld=lld",
                # Pure C++ final links do not see the Swift toolchain's
                # linkopts, so the companion CC toolchain must provide the C++
                # runtime itself.
                "-static",
                "-lc++",
            ]),
            suffix = suffix,
            triple = triple,
        )

    repository_ctx.file("BUILD.bazel", build_content)

swift_static_linux_sdk_repository = repository_rule(
    attrs = _common_attrs(),
    doc = """\
Downloads the Static Linux Swift SDK artifact bundle and defines Swift and C++
toolchains that target `{aarch64,x86_64}-swift-linux-musl` using a standalone
host toolchain's compiler.
""",
    implementation = _swift_static_linux_sdk_impl,
)
