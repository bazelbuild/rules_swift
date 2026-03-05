"""Repository rule for downloading and extracting standalone Swift toolchains.

This module provides the `standalone_toolchain` repository rule which downloads
Swift toolchains from swift.org and extracts them for use in Bazel builds.
Supports both macOS (.pkg) and Linux (.tar.gz) toolchain formats, with automatic
platform detection and appropriate extraction methods.
"""

def _full_version(short_version):
    return "swift-{}-RELEASE".format(short_version)

# Download URLs are documented in the OpenAPI spec here: https://www.swift.org/openapi/downloadswiftorg.yaml
# They're of the form: https://download.swift.org/{category}/{platform}/{version}/{file}
# To understand what category / platform / version and file refer to, we have to look at the swiftly source:
# https://github.com/swiftlang/swiftly/blob/655f8e2a1ac0bc073a5d4d2e65f6c72334d22ca4/Sources/Swiftly/Install.swift#L280
# _get_filename() and _get_download_url() below replicates some of the logic in swiftly's Install.execute() method
def _get_filename(version, platform_name_full):
    return (
        version + "-osx.pkg" if platform_name_full == "xcode" else "{}-{}.tar.gz".format(version, platform_name_full)
    )

def _get_download_url(short_version, platform_name_full):
    version = _full_version(short_version)
    return "https://download.swift.org/{category}/{platform}/{version}/{filename}".format(
        category = "swift-{}-release".format(short_version),
        platform = platform_name_full.replace(".", ""),
        version = version,
        filename = _get_filename(version, platform_name_full),
    )

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
    filename = _get_filename(_full_version(repository_ctx.attr.swift_version), repository_ctx.attr.platform)
    repository_ctx.download(
        url = _get_download_url(repository_ctx.attr.swift_version, repository_ctx.attr.platform),
        sha256 = repository_ctx.attr.sha256,
        output = filename,
    )

    if repository_ctx.attr.platform == "xcode":
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
