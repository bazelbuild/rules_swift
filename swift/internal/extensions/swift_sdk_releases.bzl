"""Swift SDK and Android NDK release version mappings.

This module defines checksums for the artifacts needed to cross-compile Swift
for platforms that are not covered by a host toolchain, using the official
"Swift SDK" artifact bundles published by swift.org (the bundles installed by
`swift sdk install`).

The Swift module format is not stable across compiler versions, so a Swift SDK
can only be used with the host toolchain from exactly the same release; the
keys of `SWIFT_SDK_RELEASES` therefore mirror the keys of `SWIFT_RELEASES` in
`swift_releases.bzl`. Checksums are published in
https://www.swift.org/api/v1/install/releases.json.
"""

SWIFT_SDK_RELEASES = {
    "6.3": {
        "android": "2f2942c4bcea7965a08665206212c66991dabe23725aeec7c4365fc91acad088",
        "static_linux": {
            "sha256": "d2078b69bdeb5c31202c10e9d8a11d6f66f82938b51a4b75f032ccb35c4c286c",
            "version": "0.1.0",
        },
        "wasm": "9fa4016ee632c7e9e906608ec3b55cf13dfc4dff44e47574c5af58064dc33fd9",
    },
    "6.3.1": {
        "android": "8193a4e96538635131a154736c8896fba0e5a1c30e065524f00ed78719bac35a",
        "static_linux": {
            "sha256": "fac05271c1f7d060bd203240ce5251d5ca902d30ac899f553765dbb3a88b97ad",
            "version": "0.1.0",
        },
        "wasm": "bd47baa20771f366d8beed7970afaa30742b2210097afd15f85427226d8f4cf2",
    },
    "6.3.2": {
        "android": "939e933549d12d28f2e0bf71019d734d309859e9773c572657ce565a81f85d68",
        "static_linux": {
            "sha256": "3fd798bef6f4408f1ea5a6f94ce4d4052830c4326ab85ebc04f983f01b3da407",
            "version": "0.1.0",
        },
        "wasm": "a61f0584c93283589f8b2f42db05c1f9a182b506c2957271402992655591dd7c",
    },
}

# The Android Swift SDK bundle ships without an NDK sysroot (its
# setup-android-sdk.sh script normally symlinks one in from a local NDK
# install), so the NDK is fetched hermetically as well. Checksums are for the
# zips at https://dl.google.com/android/repository/android-ndk-{version}-{os}.zip
DEFAULT_ANDROID_NDK_VERSION = "r27c"

ANDROID_NDK_RELEASES = {
    "r27c": {
        "darwin": "8c5685457c58a88527367d46d3f14e8c727d962c39f85344cff0c0768a73c3b7",
        "linux": "59c2f6dc96743b5daf5d1626684640b20a6bd2b1d85b13156b90333741bad5cc",
    },
}

def swift_sdk_download_url(swift_version, sdk):
    """Returns the download URL for a Swift SDK artifact bundle.

    Args:
        swift_version: The Swift release version (e.g. "6.3.2").
        sdk: The SDK kind; one of "wasm" or "android".

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

def static_linux_sdk_download_url(swift_version, sdk_version):
    """Returns the download URL for a Static Linux Swift SDK artifact bundle.

    Args:
        swift_version: The Swift release version (e.g. "6.3.2").
        sdk_version: The Static Linux SDK version (e.g. "0.1.0").

    Returns:
        The URL of the `.artifactbundle.tar.gz` for the given release.
    """
    if "-snapshot-" in swift_version:
        fail("Swift SDKs are only supported for release versions, got `{}`".format(
            swift_version,
        ))
    return (
        "https://download.swift.org/swift-{version}-release/static-sdk/" +
        "swift-{version}-RELEASE/swift-{version}-RELEASE_static-linux-{sdk_version}.artifactbundle.tar.gz"
    ).format(
        sdk_version = sdk_version,
        version = swift_version,
    )

def android_ndk_download_url(ndk_version, host_os):
    """Returns the download URL for an Android NDK release.

    Args:
        ndk_version: The NDK release name (e.g. "r27c").
        host_os: The host OS the NDK runs on; one of "darwin" or "linux".

    Returns:
        The URL of the NDK zip for the given release and host.
    """
    return "https://dl.google.com/android/repository/android-ndk-{version}-{host_os}.zip".format(
        host_os = host_os,
        version = ndk_version,
    )
