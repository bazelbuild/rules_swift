"""Repository rule for downloading and extracting standalone Swift toolchains.

This module provides the `standalone_toolchain` repository rule which downloads
Swift toolchains from swift.org and extracts them for use in Bazel builds.
Supports both macOS (.pkg) and Linux (.tar.gz) toolchain formats, with automatic
platform detection and appropriate extraction methods.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

# Download URLs are documented in the OpenAPI spec here:
# https://github.com/swiftlang/swiftly/blob/20ceb4748fd55a7e0574cf426b70f978a2636418/Sources/SwiftlyDownloadAPI/openapi.yaml
# They're of the form: https://download.swift.org/{category}/{platform}/{version}/{file}
# To understand what category / platform / version and file refer to, we have to look at the swiftly source:
# https://github.com/swiftlang/swiftly/blob/655f8e2a1ac0bc073a5d4d2e65f6c72334d22ca4/Sources/Swiftly/Install.swift#L280
# The functions below replicate some of the logic in swiftly's Install.execute() method
def _get_filename(version, platform_name_full):
    return (
        version + "-osx.pkg" if platform_name_full == "xcode" else "{}-{}.tar.gz".format(version, platform_name_full)
    )

def _swiftly_to_openapi_version(swiftly_version):
    if "-snapshot-" in swiftly_version:
        (branch, _, version) = swiftly_version.split("-", 2)
        if branch == "main":
            return "swift-DEVELOPMENT-SNAPSHOT-{}-a".format(version)
        return "swift-{}-DEVELOPMENT-SNAPSHOT-{}-a".format(branch, version)
    return "swift-{}-RELEASE".format(swiftly_version)

def _swiftly_version_to_category(swiftly_version):
    if "-snapshot-" in swiftly_version:
        (branch, _) = swiftly_version.split("-", 1)
        if branch == "main":
            return "development"
        return "swift-{}-branch".format(branch)
    return "swift-{}-release".format(swiftly_version)

def _get_download_url(category, platform, version, filename):
    return "https://download.swift.org/{category}/{platform}/{version}/{filename}".format(
        category = category,
        platform = platform,
        version = version,
        filename = filename,
    )

def get_download_url(swift_version, platform):
    category = _swiftly_version_to_category(swift_version)
    version = _swiftly_to_openapi_version(swift_version)
    filename = _get_filename(version, platform)
    return _get_download_url(category, platform.replace(".", ""), version, filename)

def _run(repository_ctx, command):
    result = repository_ctx.execute(command)

    if result.return_code:
        fail("Command failed with return code {}:\ncommand: {}\nstdout: {}\nstderr: {}".format(
            result.return_code,
            " ".join(command),
            result.stdout,
            result.stderr,
        ))

    return result.stdout.strip()

def _standalone_toolchain_impl(repository_ctx):
    url = get_download_url(repository_ctx.attr.swift_version, repository_ctx.attr.platform)
    filename = paths.basename(url)
    repository_ctx.download(
        url = url,
        sha256 = repository_ctx.attr.sha256,
        output = filename,
    )

    if filename.endswith(".pkg"):
        # .pkg file extraction can only be done on MacOS, so we will error out if the user tries to use
        # an Xcode toolchain on Linux.
        if repository_ctx.os.name != "mac os x":
            fail("Swift MacOS toolchain cannot be extracted on Linux")

        _run(repository_ctx, [
            "pkgutil",
            "--expand",
            filename,
            "tmp",
        ])
        payload_path = "tmp/{}/Payload".format(filename.replace(".pkg", "-package.pkg"))
        _run(repository_ctx, [
            "sh",
            "-c",
            "gunzip -c {} | cpio -idm".format(payload_path),
        ])
    else:
        repository_ctx.extract(
            archive = filename,
            strip_prefix = filename.removesuffix(".tar.gz"),
        )

    repository_ctx.file(".swift-version", repository_ctx.attr.swift_version)
    repository_ctx.template(
        "BUILD.bazel",
        repository_ctx.attr._build_template,
        substitutions = {
            "{exec_os}": repository_ctx.os.name,
            "{exec_arch}": repository_ctx.os.arch,
        },
    )

standalone_toolchain = repository_rule(
    implementation = _standalone_toolchain_impl,
    attrs = {
        "_build_template": attr.label(
            default = "//swift/internal:extensions/BUILD.bazel.tpl",
        ),
        "platform": attr.string(
            doc = "The host platform name in the swift package download URL",
            mandatory = True,
        ),
        "sha256": attr.string(
            doc = "The expected SHA-256 of the file downloaded. This must match the SHA-256 of the file downloaded.",
        ),
        "swift_version": attr.string(
            doc = "Version of the swift toolchain to be installed.",
            mandatory = True,
        ),
    },
)
