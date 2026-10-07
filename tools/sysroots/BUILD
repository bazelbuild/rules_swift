load("@rules_multirun//:defs.bzl", "command", "multirun")

_SYSROOTS = [
    "ubuntu22.04_amd64",
    "ubuntu22.04_arm64",
    "ubuntu24.04_amd64",
    "ubuntu24.04_arm64",
]

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
)
