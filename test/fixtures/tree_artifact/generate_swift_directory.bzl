"""A rule that generates Swift sources whose names are only known at execution time."""

def _generate_swift_directory_impl(ctx):
    directory = ctx.actions.declare_directory(ctx.attr.name + ".swift")
    args = ctx.actions.args()
    args.add(directory.path)
    inputs = []
    for path, content in ctx.attr.srcs.items():
        src = ctx.actions.declare_file("{}_srcs/{}".format(ctx.attr.name, path))
        ctx.actions.write(output = src, content = content + "\n")
        inputs.append(src)
        args.add_all([path, src])
    ctx.actions.run_shell(
        arguments = [args],
        command = """\
set -eu
directory="$1"
shift
while [ "$#" -gt 0 ]; do
  mkdir -p "$directory/$(dirname "$1")"
  cp "$2" "$directory/$1"
  shift 2
done
""",
        inputs = inputs,
        outputs = [directory],
    )
    return [DefaultInfo(files = depset([directory]))]

generate_swift_directory = rule(
    attrs = {
        "srcs": attr.string_dict(
            doc = "The contents of the generated files, keyed by their path in the directory.",
            mandatory = True,
        ),
    },
    implementation = _generate_swift_directory_impl,
)
