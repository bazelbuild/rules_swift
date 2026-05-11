"""Stamp out the explicit-modules binaries across every platform."""

load("//test:transitions.bzl", "transition_binary")

_BINARIES = [
    "c_module_imports",
    "cross_import_overlay",
    "mixed_language_bin",
    "mixed_language_explicit_bin",
    "objc_interop_implicit_bin",
]

_PLATFORMS = [
    "darwin_arm64",
    "darwin_x86_64",
    "ios_arm64",
    "ios_sim_arm64",
    "ios_x86_64",
    "tvos_arm64",
    "tvos_sim_arm64",
    "tvos_x86_64",
    "visionos_arm64",
    "visionos_sim_arm64",
    "watchos_arm64_32",
    "watchos_arm64",
    "watchos_x86_64",
]

CROSS_PLATFORM_TARGETS = [
    "{}_{}".format(binary, platform)
    for binary in _BINARIES
    for platform in _PLATFORMS
]

def cross_platform_targets(tags):  # buildifier: disable=unnamed-macro
    """Generate `<stem>_<platform>` for every (binary, platform) pair."""
    for binary in _BINARIES:
        for platform in _PLATFORMS:
            transition_binary(
                name = "{}_{}".format(binary, platform),
                target = ":{}_transitioned".format(binary),
                platform = "@build_bazel_apple_support//platforms:" + platform,
                target_compatible_with = select({
                    "//test:apple_build_tests_enabled": [],
                    "//conditions:default": ["@platforms//:incompatible"],
                }),
                tags = tags,
            )
