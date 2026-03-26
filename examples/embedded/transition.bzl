"""Generic binary transition used to test the embedded example."""

# This transition exists for the sole purpose of testing the embedded toolchain
def _generic_platform_transition(_settings, attr):
    return {
        "//command_line_option:platforms": [attr.platform],
    }

generic_platform_transition = transition(
    implementation = _generic_platform_transition,
    inputs = [
        "//command_line_option:platforms",
    ],
    outputs = ["//command_line_option:platforms"],
)

def _transition_binary_impl(ctx):
    # Just forward the files from the transitioned dep
    return [DefaultInfo(files = ctx.attr.binary[0][DefaultInfo].files)]

transition_binary = rule(
    implementation = _transition_binary_impl,
    attrs = {
        "binary": attr.label(cfg = generic_platform_transition),
        "platform": attr.label(doc = "The platform we want to transition to"),
    },
)
