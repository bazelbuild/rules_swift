"""A `config_common.FeatureFlagInfo` flag indicating if the current Xcode
version is greater than or equal to a specified minimum.
"""

def _xcode_version_at_least_impl(ctx):
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
    version = xcode_config.xcode_version()
    threshold = apple_common.dotted_version(ctx.attr.minimum_version)
    greater_or_equal = version != None and version >= threshold
    return [config_common.FeatureFlagInfo(value = "True" if greater_or_equal else "False")]

xcode_version_at_least = rule(
    implementation = _xcode_version_at_least_impl,
    attrs = {
        "minimum_version": attr.string(
            mandatory = True,
            doc = "The Xcode version threshold (e.g. `26.4`).",
        ),
        "_xcode_config": attr.label(
            default = configuration_field(
                fragment = "apple",
                name = "xcode_config_label",
            ),
        ),
    },
    doc = """\
Exposes a string-valued flag that's `"True"` when the resolved Xcode version
is greater than or equal to `minimum_version`, and `"False"` otherwise. Use
this with `config_setting(flag_values = {...: "True"})` to drive
`target_compatible_with` selects.
""",
    fragments = ["apple"],
)
