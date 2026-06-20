"""A custom rule fixture that directly returns Swift interop info."""

load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//swift:swift_interop_info.bzl", "create_swift_interop_info")

def _custom_interop_rule_impl(_ctx):
    return [
        CcInfo(),
        create_swift_interop_info(),
    ]

custom_interop_rule = rule(
    implementation = _custom_interop_rule_impl,
)
