"""Extract the PCM(s) attached to a target's `SwiftInfo`."""

load("//swift:providers.bzl", "SwiftInfo")
load("//swift:swift_clang_module_aspect.bzl", "swift_clang_module_aspect")

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

def _extract_pcm_impl(ctx):
    target = ctx.attr.target[0]
    pcms = []
    for module in target[SwiftInfo].direct_modules:
        if module.clang and module.clang.precompiled_module:
            pcms.append(module.clang.precompiled_module)
    if not pcms:
        fail("no PCM was produced for {}; check that swift.use_c_modules and swift.emit_c_module are enabled and the target is a clang module".format(
            target.label,
        ))
    return [DefaultInfo(files = depset(pcms))]

extract_pcm = rule(
    implementation = _extract_pcm_impl,
    attrs = {
        "target": attr.label(
            mandatory = True,
            cfg = _features_transition,
            aspects = [swift_clang_module_aspect],
            doc = "Any target carrying SwiftInfo with a clang precompiled module on it.",
            providers = [[SwiftInfo]],
        ),
    },
    doc = "Re-exposes any clang PCM(s) from a target's SwiftInfo as `DefaultInfo.files`.",
)
