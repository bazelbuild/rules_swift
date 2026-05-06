"""A transition that forces all PCMs to be built for the same min OS version

This works because the -target for PCM builds is actually the SDK version, not
the deployment target. This is required to dedup PCMs across different minimum
OS version transitions, which would otherwise result in PCMs that would be
identical if not for the bazel-out path.
"""

_OPTIONS = [
    "//command_line_option:ios_minimum_os",
    "//command_line_option:macos_minimum_os",
    "//command_line_option:minimum_os_version",
    "//command_line_option:tvos_minimum_os",
    "//command_line_option:watchos_minimum_os",
]

def _zero_min_os_transition_impl(_settings, _attr):
    return {flag: "0" for flag in _OPTIONS}

zero_min_os_transition = transition(
    implementation = _zero_min_os_transition_impl,
    inputs = [],
    outputs = _OPTIONS,
)
