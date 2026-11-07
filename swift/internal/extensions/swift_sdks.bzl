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

    # The bundle's clang resource directory points into the machine that built
    # it; give it the paired toolchain's builtin headers instead, as
    # setup-android-sdk.sh does. Copied, not linked, so that they are among
    # the SDK's files in a sandbox.
    clang_dir = sdk_dir_relative + "/swift-resources/usr/lib/swift/clang"
    repository_ctx.delete(clang_dir)
    result = repository_ctx.execute(["mkdir", "-p", clang_dir])
    if result.return_code == 0:
        result = repository_ctx.execute(["cp", "-R", str(clang_versions[0].get_child("include")), clang_dir + "/include"])
    if result.return_code != 0:
        fail("Couldn't copy the clang headers into the Android SDK: " + result.stderr)

    # C++ interop autolinks `c++`, which the NDK's libc++.so linker script
    # resolves to libc++_shared; this one, searched first, links the static
    # libc++ the NDK's toolchains link everything else with.
    repository_ctx.file("cxx/libc++.so", "INPUT(-lc++_static -lc++abi)\n")

    repository_ctx.template(
        "BUILD.bazel",
        repository_ctx.attr._build_template,
        substitutions = {
            "{bundle_dir}": bundle_dir,
            "{cxx_dir}": repo_root + "/cxx",
            "{lib_dir}": "{}/{}/swift-resources/usr/lib".format(repo_root, sdk_dir_relative),
            "{swift_version}": repository_ctx.attr.swift_version,
            "{toolchain_repo}": repository_ctx.attr.toolchain_repo,
        },
    )
    if hasattr(repository_ctx, "repo_metadata"):
        return repository_ctx.repo_metadata(reproducible = True)
    return None

swift_android_sdk_repository = repository_rule(
    attrs = _common_attrs() | {
        "paired_swiftc": attr.label(
            doc = """\
The `swiftc` of the standalone toolchain this SDK is paired with, used to locate
the clang builtin headers that match the clang embedded in the Swift compiler.
""",
            mandatory = True,
        ),
        "_build_template": attr.label(
            default = "//swift/internal/extensions:androidsdk.BUILD",
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
    if hasattr(repository_ctx, "repo_metadata"):
        return repository_ctx.repo_metadata(reproducible = True)
    return None

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
