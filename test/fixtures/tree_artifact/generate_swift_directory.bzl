"""A rule that generates Swift sources whose names are only known at execution time."""

def _generate_swift_directory_impl(ctx):
    directory = ctx.actions.declare_directory(ctx.attr.name + ".swift")
    ctx.actions.run_shell(
        outputs = [directory],
        arguments = [directory.path],
        command = """\
set -eu
mkdir -p "$1/Nested"
echo 'public struct Generated { public init() {} }' > "$1/Generated.swift"
echo 'public let nestedValue = 41' > "$1/Nested/Nested.swift"
""",
    )
    return [DefaultInfo(files = depset([directory]))]

generate_swift_directory = rule(
    implementation = _generate_swift_directory_impl,
)
