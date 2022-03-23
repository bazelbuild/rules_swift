"""Simple rule to emulate apple_static_framework_import"""

def _impl(ctx):
    binary1 = ctx.actions.declare_file("framework1.framework/framework")
    ctx.actions.write(binary1, "empty")
    binary2 = ctx.actions.declare_file("framework2.framework/framework")
    ctx.actions.write(binary2, "empty")
    return apple_common.new_objc_provider(
        static_framework_file = depset([binary1, binary2]),
    )

fake_framework = rule(
    implementation = _impl,
)
