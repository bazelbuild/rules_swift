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

def _swift_android_sdk_impl(repository_ctx):
    bundle_dir = _download_sdk_bundle(repository_ctx)
    repo_root = "external/" + repository_ctx.name
    sdk_dir_relative = bundle_dir + "/swift-android"
    if not repository_ctx.path(sdk_dir_relative + "/swift-sdk.json").exists:
        fail("The Android Swift SDK bundle has an unexpected layout; " +
             "missing {}/{}/swift-sdk.json".format(repo_root, sdk_dir_relative))

    # The clang headers are provided by the Swift toolchain, not the Android SDK bundle
    paired_usr = repository_ctx.path(repository_ctx.attr.paired_swiftc).dirname.dirname
    clang_versions = paired_usr.get_child("lib", "clang").readdir()
    if len(clang_versions) != 1:
        fail("Expected exactly one clang version directory in the host " +
             "toolchain, found: " + str(clang_versions))
    clang_builtin_headers = _execroot_relative_path(clang_versions[0].get_child("include"))

    repository_ctx.template(
        "BUILD.bazel",
        repository_ctx.attr._build_template,
        substitutions = {
            "{bundle_dir}": bundle_dir,
            "{clang_builtin_headers}": clang_builtin_headers,
            "{lib_dir}": "{}/{}/swift-resources/usr/lib".format(repo_root, sdk_dir_relative),
            "{swift_version}": repository_ctx.attr.swift_version,
            "{toolchain_repo}": repository_ctx.attr.toolchain_repo,
        },
    )

swift_android_sdk_repository = repository_rule(
    attrs = _common_attrs() | {
        "_build_template": attr.label(
            default = "//swift/internal/extensions:androidsdk.BUILD",
        ),
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
    repo_root = "external/" + repository_ctx.name
    sdk_dir = "{}/{}/{}".format(
        repo_root,
        bundle_dir,
        "{0}/wasm32-unknown-wasip1".format(bundle_dir.removesuffix(".artifactbundle")),
    )
    if not repository_ctx.path(sdk_dir.removeprefix(repo_root + "/")).exists:
        fail("The WebAssembly Swift SDK bundle has an unexpected layout; missing " + sdk_dir)

    repository_ctx.template(
        "BUILD.bazel",
        repository_ctx.attr._build_template,
        substitutions = {
            "{bundle_dir}": bundle_dir,
            "{sdk_dir}": sdk_dir,
            "{swift_version}": repository_ctx.attr.swift_version,
            "{toolchain_repo}": repository_ctx.attr.toolchain_repo,
        },
    )

swift_wasm_sdk_repository = repository_rule(
    attrs = _common_attrs() | {
        "_build_template": attr.label(
            default = "//swift/internal/extensions:wasmsdk.BUILD",
        ),
    },
    doc = """\
Downloads the WebAssembly Swift SDK artifact bundle and defines Swift and C++
toolchains that target `wasm32-unknown-wasip1` using a standalone host
toolchain's compiler.
""",
    implementation = _swift_wasm_sdk_impl,
)
