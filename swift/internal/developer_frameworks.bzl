""" Functions for fetching developer framework paths """

load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    ":utils.bzl",
    "compact",
    "is_xcode_at_least_version",
)

def platform_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config):
    """Returns the Developer framework directory for the platform.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        xcode_config: The Xcode configuration.

    Returns:
        The path to the Developer framework directory for the platform if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their
    # platform root, except for watchOS prior to Xcode 12.5.
    platform_type = apple_fragment.single_arch_platform.platform_type
    if (
        platform_type == apple_common.platform_type.watchos and
        not is_xcode_at_least_version(xcode_config, "12.5")
    ):
        return None

    return apple_toolchain.platform_developer_framework_dir(apple_fragment)

def swift_developer_lib_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config):
    """Returns the directory containing extra Swift developer libraries.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        xcode_config: The Xcode configuration.

    Returns:
        The directory containing extra Swift-specific development libraries and
        swiftmodules.
    """

    platform_framework_dir = platform_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )

    return paths.join(
        paths.dirname(paths.dirname(platform_framework_dir)),
        "usr",
        "lib",
    )

def developer_framework_paths(
        apple_fragment,
        xcode_config):
    """Returns the developer framework paths for the given apple fragment and xcode configuration.

    Args:
        apple_fragment: The `apple` configuration fragment.
        xcode_config: The Xcode configuration.

    Returns:
        A list of paths to developer frameworks
    """
    apple_toolchain = apple_common.apple_toolchain()
    platform_developer_framework = platform_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )
    sdk_developer_framework = _sdk_developer_framework_dir(
        apple_toolchain,
        apple_fragment,
        xcode_config,
    )
    return compact([
        platform_developer_framework,
        sdk_developer_framework,
    ])

def _sdk_developer_framework_dir(apple_toolchain, apple_fragment, xcode_config):
    """Returns the Developer framework directory for the SDK.

    Args:
        apple_fragment: The `apple` configuration fragment.
        apple_toolchain: The `apple_common.apple_toolchain()` object.
        xcode_config: The Xcode configuration.

    Returns:
        The path to the Developer framework directory for the SDK if one
        exists, otherwise `None`.
    """

    # All platforms have a `Developer/Library/Frameworks` directory in their SDK
    # root except for macOS (all versions of Xcode so far), and watchOS (prior
    # to Xcode 12.5).
    platform_type = apple_fragment.single_arch_platform.platform_type
    if (
        platform_type == apple_common.platform_type.macos or
        (
            platform_type == apple_common.platform_type.watchos and
            not is_xcode_at_least_version(xcode_config, "12.5")
        )
    ):
        return None

    return paths.join(apple_toolchain.sdk_dir(), "Developer/Library/Frameworks")
