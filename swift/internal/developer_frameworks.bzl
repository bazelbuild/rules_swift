""" Functions for fetching developer framework paths """

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":utils.bzl",
    "compact",
    "is_xcode_at_least_version",
)
load(":target_triples.bzl", "target_triples")

# Maps (operating system, environment) pairs from target triples to the legacy
# Bazel core `apple_common.platform` values, since we still use some APIs that
# require these.
_TRIPLE_OS_TO_PLATFORM = {
    ("ios", None): apple_common.platform.ios_device,
    ("ios", "simulator"): apple_common.platform.ios_simulator,
    ("macos", None): apple_common.platform.macos,
    ("tvos", None): apple_common.platform.tvos_device,
    ("tvos", "simulator"): apple_common.platform.tvos_simulator,
    ("watchos", None): apple_common.platform.watchos_device,
    ("watchos", "simulator"): apple_common.platform.watchos_simulator,
}

def _bazel_apple_platform(target_triple):
    """Returns the `apple_common.platform` value for the given target triple."""
    return _TRIPLE_OS_TO_PLATFORM[(
        target_triples.unversioned_os(target_triple),
        target_triple.environment,
    )]

def platform_developer_framework_dir(
        apple_toolchain,
        target_triple,
        xcode_config):
    """Returns the Developer framework directory for the platform.

    Args:
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        target_triple: The triple of the platform being targeted.
        xcode_config: The Xcode configuration.

    Returns:
        The path to the Developer framework directory for the platform if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their
    # platform root, except for watchOS prior to Xcode 12.5.
    if (
        target_triples.unversioned_os(target_triple) == "watchos" and
        not is_xcode_at_least_version(xcode_config, "12.5")
    ):
        return None

    return paths.join(
        apple_toolchain.developer_dir(),
        "Platforms",
        "{}.platform".format(
            _bazel_apple_platform(target_triple).name_in_plist,
        ),
        "Developer/Library/Frameworks",
    )

def swift_developer_lib_dir(
        apple_toolchain,
        target_triple,
        xcode_config):
    """Returns the directory containing extra Swift developer libraries.

    Args:
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        target_triple: The triple of the platform being targeted.
        xcode_config: The Xcode configuration.

    Returns:
        The directory containing extra Swift-specific development libraries and
        swiftmodules.
    """
    platform_framework_dir = platform_developer_framework_dir(
        apple_toolchain,
        target_triple,
        xcode_config,
    )

    return paths.join(
        paths.dirname(paths.dirname(platform_framework_dir)),
        "usr",
        "lib",
    )

def developer_framework_paths(
        target_triple,
        xcode_config):
    """Returns the developer framework paths for the given apple fragment and \
    xcode configuration.

    Args:
        target_triple: The triple of the platform being targeted.
        xcode_config: The Xcode configuration.

    Returns:
        A list of paths to developer frameworks
    """
    apple_toolchain = apple_common.apple_toolchain()
    platform_developer_framework = platform_developer_framework_dir(
        apple_toolchain,
        target_triple,
        xcode_config,
    )
    sdk_developer_framework = _sdk_developer_framework_dir(
        apple_toolchain,
        target_triple,
        xcode_config,
    )
    return compact([
        platform_developer_framework,
        sdk_developer_framework,
    ])

def _sdk_developer_framework_dir(apple_toolchain, target_triple, xcode_config):
    """Returns the Developer framework directory for the SDK.

    Args:
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        target_triple: The triple of the platform being targeted.
        xcode_config: The Xcode configuration.

    Returns:
        The path to the Developer framework directory for the SDK if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their SDK
    # root except for macOS (all versions of Xcode so far), and watchOS (prior
    # to Xcode 12.5).
    os = target_triples.unversioned_os(target_triple)
    if (os == "macos" or
        (os == "watchos" and
         not is_xcode_at_least_version(xcode_config, "12.5"))):
        return None

    return paths.join(apple_toolchain.sdk_dir(), "Developer/Library/Frameworks")
