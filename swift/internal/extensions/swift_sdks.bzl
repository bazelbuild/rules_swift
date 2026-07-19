"""Shared building blocks for Swift SDK repository rules.

A "Swift SDK" is an artifact bundle published by swift.org for cross-compiling
Swift to a platform the host toolchain cannot target by itself (the bundles that
`swift sdk install` consumes). The per-platform extensions (`android_sdk`,
`wasm_sdk`) define repository rules that download such a bundle and generate a
`swift_toolchain` for the target; this module holds the helpers and BUILD-file
templates they share. Android's C/C++ compilation and linking go through a
separately registered Android cc toolchain (e.g. `@androidndk//:all`), while the
WebAssembly repository also generates a rules_cc `cc_toolchain` that drives the
paired toolchain's clang.

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

def _swift_sdk_json_path(repository_ctx, bundle_dir):
    """Locates the default `swift-sdk.json` via the bundle's `info.json`.

    An artifact bundle's `info.json` lists one or more `swiftSDK` artifacts,
    each with a variant path to a `swift-sdk.json` metadata file. Bundles that
    also ship an Embedded Swift variant name its metadata
    `embedded-swift-sdk.json`; the default (full-stdlib) artifact is the one
    whose metadata file is named exactly `swift-sdk.json`.

    Returns:
        The path of the default artifact's `swift-sdk.json`, relative to the
        repository root.
    """
    info = json.decode(repository_ctx.read(bundle_dir + "/info.json"))
    artifacts = info.get("artifacts")
    if type(artifacts) != "dict":
        fail("The Swift SDK bundle has an unexpected layout; " +
             "info.json is missing `artifacts`.")

    candidates = []
    for artifact in artifacts.values():
        if artifact.get("type") != "swiftSDK":
            continue
        for variant in artifact.get("variants", []):
            path = variant.get("path", "")
            if path.split("/")[-1] == "swift-sdk.json":
                candidates.append(path)
    if len(candidates) != 1:
        fail(("The Swift SDK bundle has an unexpected layout; expected " +
              "info.json to reference exactly one `swift-sdk.json` variant, " +
              "found: {}").format(candidates))
    return "{}/{}".format(bundle_dir, candidates[0])

def _swift_sdk_target_settings(repository_ctx, sdk_json_path):
    """Parses a `swift-sdk.json`, returning its single triple and settings.

    Returns:
        A `(triple, settings)` tuple, where `settings` is the decoded
        per-triple dictionary (`sdkRootPath`, `swiftStaticResourcesPath`,
        `toolsetPaths`, ...).
    """
    metadata = json.decode(repository_ctx.read(sdk_json_path))
    target_triples = metadata.get("targetTriples")
    if type(target_triples) != "dict":
        fail("The Swift SDK bundle has an unexpected layout; " +
             "{} is missing `targetTriples`.".format(sdk_json_path))
    if len(target_triples) != 1:
        fail(("Expected {} to declare exactly one target triple, " +
              "got: {}").format(sdk_json_path, target_triples.keys()))
    triple = target_triples.keys()[0]
    return triple, target_triples[triple]

def merged_toolset_options(toolsets, context):
    """Merges decoded `toolset.json` dictionaries into per-tool option lists.

    A Swift SDK's `swift-sdk.json` may reference several toolset files via
    `toolsetPaths`; SwiftPM applies them in order, with `extraCLIOptions`
    accumulating. `rootPath` and per-tool executable overrides are ignored:
    the generated toolchains always drive the paired standalone toolchain's
    own `swiftc`/`clang`.

    Args:
        toolsets: Decoded `toolset.json` dictionaries, in `toolsetPaths` order.
        context: A human-readable location (bundle URL or path) for error
            messages.

    Returns:
        A `struct` with `c_compiler`, `cxx_compiler`, `linker`, and
        `swift_compiler` fields, each the merged `extraCLIOptions` list for
        that tool.
    """
    merged = {
        "cCompiler": [],
        "cxxCompiler": [],
        "linker": [],
        "swiftCompiler": [],
    }
    for toolset in toolsets:
        for tool, options in merged.items():
            extra = toolset.get(tool, {}).get("extraCLIOptions", [])
            for option in extra:
                if type(option) != "string":
                    fail(("Expected `{}.extraCLIOptions` in the toolset " +
                          "metadata of {} to be a list of strings, " +
                          "got: {}").format(tool, context, extra))
            options.extend(extra)
    return struct(
        c_compiler = merged["cCompiler"],
        cxx_compiler = merged["cxxCompiler"],
        linker = merged["linker"],
        swift_compiler = merged["swiftCompiler"],
    )

def linker_options_to_clang_args(options, context):
    """Translates raw linker options from a toolset into clang driver args.

    SwiftPM invokes the linker named by the toolset directly, so a toolset's
    `linker.extraCLIOptions` are raw `wasm-ld`/`ld` flags. The generated
    toolchains link through the clang driver instead, so each option is
    forwarded with `-Wl,`.

    Args:
        options: The toolset's merged `linker.extraCLIOptions`.
        context: A human-readable location (bundle URL or path) for error
            messages.

    Returns:
        The options wrapped for the clang driver.
    """
    for option in options:
        if "," in option:
            fail(("Linker option `{}` from the toolset metadata of {} " +
                  "contains a comma and cannot be forwarded via " +
                  "`-Wl,`.").format(option, context))
    return ["-Wl," + option for option in options]

def _toolset_options(repository_ctx, sdk_dir_relative, target_settings, triple, context):
    """Reads and merges the toolsets referenced by a `swift-sdk.json`."""
    toolsets = []
    for toolset_path in target_settings.get("toolsetPaths", []):
        toolsets.append(json.decode(repository_ctx.read("{}/{}".format(
            sdk_dir_relative,
            _relative_metadata_path(toolset_path, "toolsetPaths", triple),
        ))))
    return merged_toolset_options(toolsets, context)

def _bzl_list_tail(flags, indent):
    """Formats flags as list elements appended after an existing list entry.

    Each flag becomes its own line (leading newline + `indent`), so the result
    can be substituted immediately after the trailing comma of the last static
    element of a BUILD-file list literal.
    """
    return "".join(["\n{}\"{}\",".format(indent, flag) for flag in flags])

def _wasm_toolset_substitutions(toolset, context):
    """Returns BUILD-template substitutions carrying the SDK's toolset options.

    The C compiler options apply to both C and C++ compilations (the wasm cc
    toolchain does not distinguish them); a toolset with *different* C++
    options is rejected rather than half-applied. For the single-threaded
    swift.org bundle the toolset carries only `-static-stdlib` for `swiftc`;
    the wasi-threads bundle additionally carries the atomics/pthread compile
    flags and the shared-memory link flags.
    """
    if toolset.cxx_compiler and toolset.cxx_compiler != toolset.c_compiler:
        fail(("The toolset metadata of {} has `cxxCompiler` options that " +
              "differ from its `cCompiler` options; this is not " +
              "supported.").format(context))
    link_args = linker_options_to_clang_args(toolset.linker, context)
    return {
        "{cc_toolset_compile_args}": _bzl_list_tail(
            toolset.c_compiler,
            "        ",
        ),
        "{cc_toolset_link_args}": _bzl_list_tail(link_args, "        "),
        "{swift_toolset_copts}": _bzl_list_tail(
            toolset.swift_compiler,
            "        ",
        ),
        "{swift_toolset_linkopts}": _bzl_list_tail(link_args, "        "),
    }

def _swift_wasm_sdk_impl(repository_ctx):
    threads = repository_ctx.attr.threads
    expected_triple = "wasm32-unknown-wasip1-threads" if threads else "wasm32-unknown-wasip1"

    bundle_dir = _download_sdk_bundle(repository_ctx)
    repo_root = "external/" + repository_ctx.name
    context = repository_ctx.attr.url

    sdk_json_path = _swift_sdk_json_path(repository_ctx, bundle_dir)
    sdk_dir_relative = sdk_json_path.rsplit("/", 1)[0]
    triple, target_settings = _swift_sdk_target_settings(
        repository_ctx,
        sdk_json_path,
    )
    if triple != expected_triple:
        fail(("The WebAssembly Swift SDK bundle at {} targets `{}`, but this " +
              "repository was configured for `{}`; pass `threads = {}` to " +
              "`swift.wasm_sdk` to match the bundle.").format(
            context,
            triple,
            expected_triple,
            "False" if threads else "True",
        ))

    sdk_dir = "{}/{}".format(repo_root, sdk_dir_relative)
    resource_dir = "{}/{}".format(sdk_dir, _relative_metadata_path(
        target_settings.get("swiftStaticResourcesPath"),
        "swiftStaticResourcesPath",
        triple,
    ))
    sdkroot = "{}/{}".format(sdk_dir, _relative_metadata_path(
        target_settings.get("sdkRootPath"),
        "sdkRootPath",
        triple,
    ))
    toolset = _toolset_options(
        repository_ctx,
        sdk_dir_relative,
        target_settings,
        triple,
        context,
    )

    substitutions = {
        "{bundle_dir}": bundle_dir,
        "{resource_dir}": resource_dir,
        "{sdkroot}": sdkroot,
        "{swift_version}": repository_ctx.attr.swift_version,
        "{target_triple}": triple,
        "{toolchain_repo}": repository_ctx.attr.toolchain_repo,
    }
    substitutions.update(_wasm_toolset_substitutions(toolset, context))

    repository_ctx.template(
        "BUILD.bazel",
        repository_ctx.attr._build_template,
        substitutions = substitutions,
    )

swift_wasm_sdk_repository = repository_rule(
    attrs = _common_attrs() | {
        "threads": attr.bool(
            default = False,
            doc = """\
If `True`, target `wasm32-unknown-wasip1-threads` (shared memory + atomics +
wasi-threads) instead of the single-threaded `wasm32-unknown-wasip1`.
""",
        ),
        "_build_template": attr.label(
            default = "//swift/internal/extensions:wasmsdk.BUILD",
        ),
    },
    doc = """\
Downloads the WebAssembly Swift SDK artifact bundle and defines Swift and C++
toolchains that target `wasm32-unknown-wasip1` (or
`wasm32-unknown-wasip1-threads` when `threads = True`) using a standalone host
toolchain's compiler.
""",
    implementation = _swift_wasm_sdk_impl,
)
