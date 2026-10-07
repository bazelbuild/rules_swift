load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")
load("@rules_multirun//:defs.bzl", "command", "multirun")

# bazel_linux_packages requires Linux host tools even when loading its repos.
# Filter during package loading: select() and target compatibility alone still
# expose every dependency to unconfigured queries such as rdeps(//..., ...).
_IS_LINUX_HOST = "@platforms//os:linux" in HOST_CONSTRAINTS

_SYSROOTS = [
    "ubuntu22.04_amd64",
    "ubuntu22.04_arm64",
    "ubuntu24.04_amd64",
    "ubuntu24.04_arm64",
] if _IS_LINUX_HOST else []

[
    command(
        name = sysroot,
        arguments = ["$$(rlocation $(rlocationpath @swift_{}_sysroot//:lock).json)".format(sysroot)],
        command = "@swift_{}_sysroot//:lock".format(sysroot),
        data = ["@swift_{}_sysroot//:lock".format(sysroot)],
    )
    for sysroot in _SYSROOTS
]

multirun(
    name = "lock",
    commands = _SYSROOTS,
    jobs = 0,
    target_compatible_with = [] if _IS_LINUX_HOST else ["@platforms//:incompatible"],
)
