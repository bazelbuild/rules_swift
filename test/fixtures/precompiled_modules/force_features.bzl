"""Transition wrapper that forces a caller-supplied set of features on."""

def _force_features_transition_impl(settings, attr):
    return {
        "//command_line_option:features": settings["//command_line_option:features"] + attr.transitive_features,
    }

_force_features_transition = transition(
    implementation = _force_features_transition_impl,
    inputs = ["//command_line_option:features"],
    outputs = ["//command_line_option:features"],
)

def _force_features_binary_impl(ctx):
    return [DefaultInfo(files = ctx.attr.binary[0][DefaultInfo].files)]

force_features_binary = rule(
    implementation = _force_features_binary_impl,
    attrs = {
        "binary": attr.label(
            mandatory = True,
            cfg = _force_features_transition,
            doc = "The binary target to build under the feature transition.",
        ),
        "transitive_features": attr.string_list(
            mandatory = True,
            doc = (
                "Feature strings appended to `//command_line_option:features` " +
                "when analyzing `binary`."
            ),
        ),
    },
    doc = (
        "Forwards `DefaultInfo` from a binary built after appending `transitive_features` to the `--features` command line option."
    ),
)
