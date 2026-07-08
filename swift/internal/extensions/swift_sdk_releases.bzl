"""Swift SDK release helpers."""

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
