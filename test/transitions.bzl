"""Custom transition rules helpful for tests."""

def _force_features_transition_impl(settings, attr):
    return {
        "//command_line_option:features": settings["//command_line_option:features"] + attr.transitive_features,
        "//command_line_option:host_features": settings["//command_line_option:host_features"] + attr.transitive_features,
    }

_force_features_transition = transition(
    implementation = _force_features_transition_impl,
    inputs = [
        "//command_line_option:features",
        "//command_line_option:host_features",
    ],
    outputs = [
        "//command_line_option:features",
        "//command_line_option:host_features",
    ],
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
            doc = "Feature strings appended to `//command_line_option:features` when analyzing `binary`.",
        ),
    },
    doc = "Forwards `DefaultInfo` from a binary built after appending `transitive_features` to the `--features` command line option.",
)

def _force_features_test_impl(ctx):
    target = ctx.attr.binary[0]
    forwarded = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = forwarded,
        target_file = target.files_to_run.executable,
        is_executable = True,
    )

    return [
        DefaultInfo(executable = forwarded, runfiles = target[DefaultInfo].default_runfiles),
    ]

force_features_test = rule(
    implementation = _force_features_test_impl,
    attrs = {
        "binary": attr.label(
            mandatory = True,
            cfg = _force_features_transition,
            doc = "The test target to run under the feature transition.",
        ),
        "transitive_features": attr.string_list(
            mandatory = True,
            doc = "Feature strings appended to `//command_line_option:features` when analyzing `binary`.",
        ),
    },
    doc = "Forwards a test target's executable and runfiles after appending `transitive_features` to the `--features` command line option.",
    test = True,
)

def _platform_transition_impl(_settings, attr):
    return {"//command_line_option:platforms": [attr.platform]}

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _platform_transition_binary_impl(ctx):
    return [DefaultInfo(files = ctx.attr.binary[0][DefaultInfo].files)]

platform_transition_binary = rule(
    implementation = _platform_transition_binary_impl,
    attrs = {
        "binary": attr.label(
            mandatory = True,
            cfg = _platform_transition,
            doc = "The target to build under the platform transition.",
        ),
        "platform": attr.string(
            mandatory = True,
            doc = "The target platform label (e.g. `@build_bazel_apple_support//platforms:macos_x86_64`).",
        ),
    },
)
