"""A transition that forces system modules to use the current SDK as min OS.

This works because the -target for PCM builds is actually the SDK version, not
the deployment target. This is required to dedup PCMs across different minimum
OS version transitions, which would otherwise result in PCMs that would be
identical if not for the bazel-out path.
"""

_GENERIC_MIN_OS_OPTION = "//command_line_option:minimum_os_version"

_MIN_OS_OPTIONS = [
    "//command_line_option:ios_minimum_os",
    "//command_line_option:macos_minimum_os",
    "//command_line_option:tvos_minimum_os",
    "//command_line_option:watchos_minimum_os",
    _GENERIC_MIN_OS_OPTION,
]

_SDK_NAME_TO_MIN_OS_OPTION = {
    "AppleTVOS": "//command_line_option:tvos_minimum_os",
    "AppleTVSimulator": "//command_line_option:tvos_minimum_os",
    "iPhoneOS": "//command_line_option:ios_minimum_os",
    "iPhoneSimulator": "//command_line_option:ios_minimum_os",
    "MacOSX": "//command_line_option:macos_minimum_os",
    "WatchOS": "//command_line_option:watchos_minimum_os",
    "WatchSimulator": "//command_line_option:watchos_minimum_os",
}

def zero_min_os_transition_attrs():
    return {
        "sdk_name": attr.string(
            doc = "The SDK name whose version should be used for `--minimum_os_version`.",
        ),
        "sdk_version": attr.string(
            doc = "The SDK version to use as the minimum OS version.",
        ),
    }

def _sdk_min_os_transition_impl(settings, attr):
    # Empty module group
    if not attr.sdk_name:
        return settings

    if not attr.sdk_version:
        fail("sdk_version must be set when sdk_name is set.")

    values = {option: settings[option] for option in _MIN_OS_OPTIONS}
    current_min_os_option = _SDK_NAME_TO_MIN_OS_OPTION.get(attr.sdk_name)
    if current_min_os_option:
        values[current_min_os_option] = attr.sdk_version
    values[_GENERIC_MIN_OS_OPTION] = attr.sdk_version
    return values

zero_min_os_transition = transition(
    implementation = _sdk_min_os_transition_impl,
    inputs = _MIN_OS_OPTIONS,
    outputs = _MIN_OS_OPTIONS,
)
