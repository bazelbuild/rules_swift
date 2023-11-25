"""A rule that generates a Swift library from protocol buffer sources."""

load("@rules_proto//proto:defs.bzl", "ProtoInfo")
load(":providers.bzl", "SwiftInfo", "SwiftProtoInfo")
load(":transitions.bzl", "proto_compiler_transition")

def _swift_proto_library_impl(ctx):
    pass

new_swift_proto_library = rule(
    attrs = {
        "protos": attr.label_list(
            providers = [ProtoInfo],
            default = [],
        ),
        "deps": attr.label_list(
            aspects = [swift_protoc_gen_aspect],
            doc = """\
Exactly one `proto_library` target (or any target that propagates a `proto`
provider) from which the Swift library should be generated.
""",
            providers = [SwiftInfo],
        ),
        "_allowlist_function_transition": attr.label(
            default = Label(
                "@bazel_tools//tools/allowlists/function_transition_allowlist",
            ),
        ),
    },
    cfg = proto_compiler_transition,
            doc = """\
Generates a Swift library from protocol buffer sources.

```python
proto_library(
    name = "foo",
    srcs = ["foo.proto"],
)

swift_proto_library(
    name = "foo_swift",
    protos = [":foo"],
)
```

You should have one proto_library and one swift_proto_library per proto package.
If your protos depend on protos from other packages, add a dependency between
the swift_proto_library targets which mirrors the dependency between the proto targets.

```python
proto_library(
    name = "bar",
    srcs = ["bar.proto"],
    deps = [":foo"],
)

swift_proto_library(
    name = "bar_swift",
    protos = [":bar"],
    deps = [":foo_swift"],
)
```
""",
    implementation = _swift_proto_library_impl,
)
