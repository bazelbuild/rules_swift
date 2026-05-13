"""Custom transition rules helpful for tests."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_cc//cc/common:objc_info.bzl", "ObjcInfo")
load("//swift:providers.bzl", "SwiftInfo")

_COMPILATION_MODE = "//command_line_option:compilation_mode"
_FEATURES = "//command_line_option:features"
_HOST_FEATURES = "//command_line_option:host_features"
_IOS_MINIMUM_OS = "//command_line_option:ios_minimum_os"
_MACOS_MINIMUM_OS = "//command_line_option:macos_minimum_os"
_PLATFORMS = "//command_line_option:platforms"
_TVOS_MINIMUM_OS = "//command_line_option:tvos_minimum_os"

_TRANSITION_OPTIONS = [
    _COMPILATION_MODE,
    _FEATURES,
    _HOST_FEATURES,
    _IOS_MINIMUM_OS,
    _MACOS_MINIMUM_OS,
    _PLATFORMS,
    _TVOS_MINIMUM_OS,
]

def _transition_impl(settings, attr):
    return {
        _COMPILATION_MODE: attr.compilation_mode or settings[_COMPILATION_MODE],
        _FEATURES: settings[_FEATURES] + attr.transitive_features,
        _HOST_FEATURES: settings[_HOST_FEATURES] + attr.transitive_features,
        _IOS_MINIMUM_OS: attr.minimum_os or settings[_IOS_MINIMUM_OS],
        _MACOS_MINIMUM_OS: attr.minimum_os or settings[_MACOS_MINIMUM_OS],
        _PLATFORMS: [attr.platform] if attr.platform else settings[_PLATFORMS],
        _TVOS_MINIMUM_OS: attr.minimum_os or settings[_TVOS_MINIMUM_OS],
    }

_transition = transition(
    implementation = _transition_impl,
    inputs = _TRANSITION_OPTIONS,
    outputs = _TRANSITION_OPTIONS,
)

_TRANSITION_ATTRS = {
    "compilation_mode": attr.string(
        default = "",
        doc = (
            "Optional value to force `--compilation_mode` to (e.g. `dbg`, " +
            "`opt`). Empty (the default) leaves the inherited setting alone."
        ),
        values = ["", "dbg", "fastbuild", "opt"],
    ),
    "minimum_os": attr.string(
        doc = "Optional value to set the Apple platform minimum OS to.",
    ),
    "platform": attr.string(
        doc = "Optional target platform label (e.g. `@build_bazel_apple_support//platforms:macos_x86_64`).",
    ),
    "transitive_features": attr.string_list(
        doc = "Feature strings appended to `//command_line_option:features` and `//command_line_option:host_features`.",
    ),
}

def _attrs(target_doc):
    attrs = dict(_TRANSITION_ATTRS)
    attrs["target"] = attr.label(
        mandatory = True,
        cfg = _transition,
        doc = target_doc,
    )
    return attrs

def _forwarded_providers(target):
    providers = []
    if SwiftInfo in target:
        providers.append(target[SwiftInfo])
    if CcInfo in target:
        providers.append(target[CcInfo])
    if ObjcInfo in target:
        providers.append(target[ObjcInfo])
    return providers + [
        DefaultInfo(files = target[DefaultInfo].files),
    ]

def _transition_binary_impl(ctx):
    return _forwarded_providers(ctx.attr.target[0])

transition_binary = rule(
    implementation = _transition_binary_impl,
    attrs = _attrs("The target to build under the transition."),
    doc = "Forwards providers from a target built under test-controlled transition settings.",
)

def _transition_test_impl(ctx):
    target = ctx.attr.target[0]
    forwarded = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = forwarded,
        target_file = target.files_to_run.executable,
        is_executable = True,
    )

    return [
        DefaultInfo(executable = forwarded, runfiles = target[DefaultInfo].default_runfiles),
    ]

transition_test = rule(
    implementation = _transition_test_impl,
    attrs = _attrs("The test target to run under the transition."),
    doc = "Forwards a test target's executable and runfiles after applying test-controlled transition settings.",
    test = True,
)
