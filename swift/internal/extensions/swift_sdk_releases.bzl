"""Swift SDK release version mappings.

Checksums for the official "Swift SDK" artifact bundles published by swift.org
(the bundles installed by `swift sdk install`), used to cross-compile Swift to
platforms not covered by a host toolchain.

The Swift module format is not stable across compiler versions, so a Swift SDK
can only be used with the host toolchain from exactly the same release; the
keys of `SWIFT_SDK_RELEASES` therefore mirror the keys of `SWIFT_RELEASES` in
`swift_releases.bzl`. Checksums are published in
https://www.swift.org/api/v1/install/releases.json.
"""

SWIFT_SDK_RELEASES = {
    "6.3.2": {
        "android": "939e933549d12d28f2e0bf71019d734d309859e9773c572657ce565a81f85d68",
    },
}

def swift_sdk_download_url(swift_version, sdk):
    """Returns the download URL for a Swift SDK artifact bundle.

    Args:
        swift_version: The Swift release version (e.g. "6.3.2").
        sdk: The SDK kind (e.g. "android").

    Returns:
        The URL of the `.artifactbundle.tar.gz` for the given release.
    """
    if "-snapshot-" in swift_version:
        fail("Swift SDKs are only supported for release versions, got `{}`".format(
            swift_version,
        ))
    return (
        "https://download.swift.org/swift-{version}-release/{sdk}-sdk/" +
        "swift-{version}-RELEASE/swift-{version}-RELEASE_{sdk}.artifactbundle.tar.gz"
    ).format(
        sdk = sdk,
        version = swift_version,
    )
