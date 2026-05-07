"""Extract the `.swiftmodule` from a target's `SwiftInfo`."""

load("//swift:providers.bzl", "SwiftInfo")

_FEATURES = [
    "swift.use_c_modules",
    "swift.emit_c_module",
]

def _features_transition_impl(settings, _attr):
    features = list(settings["//command_line_option:features"])
    for feature in _FEATURES:
        if feature not in features:
            features.append(feature)
    return {"//command_line_option:features": features}

_features_transition = transition(
    implementation = _features_transition_impl,
    inputs = ["//command_line_option:features"],
    outputs = ["//command_line_option:features"],
)

def _extract_swiftmodule_impl(ctx):
    target = ctx.attr.target[0]
    files = []
    for module in target[SwiftInfo].direct_modules:
        if module.swift and module.swift.swiftmodule:
            files.append(module.swift.swiftmodule)
    if not files:
        fail("no .swiftmodule produced for {}; check that the target is a Swift module".format(
            target.label,
        ))
    return [DefaultInfo(files = depset(files))]

extract_swiftmodule = rule(
    implementation = _extract_swiftmodule_impl,
    attrs = {
        "target": attr.label(
            mandatory = True,
            cfg = _features_transition,
            doc = "A Swift target carrying SwiftInfo whose `.swiftmodule` should be extracted.",
            providers = [[SwiftInfo]],
        ),
    },
    doc = "Re-exposes the `.swiftmodule` from a target's `SwiftInfo` as `DefaultInfo.files`.",
)
