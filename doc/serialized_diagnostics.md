# Serialized compiler diagnostics

Enable `swift.serialized_diagnostics_file` to have Swift compilation actions
produce serialized diagnostics (`.dia`) files alongside their object files:

```sh
bazel build //path/to:target --features=swift.serialized_diagnostics_file
```

These files contain structured diagnostics, including source locations and
available fix-its. Whole-module compilation produces one diagnostics file for
the module; other compilation modes produce one per source file. Source trees
produce corresponding directories of diagnostics files. Diagnostics are declared
action outputs, so they participate in caching and remote execution.

The feature does not add a provider or an output group. Consumers can collect
the files from compilation action outputs using an aspect. For example, a
consumer-owned `diagnostics.bzl` can collect diagnostics through `deps` and
`private_deps`:

```starlark
_DiagnosticsInfo = provider(fields = ["files"])

_ATTRIBUTES = ["deps", "private_deps"]

def _diagnostics_impl(target, ctx):
    direct = [
        output
        for action in target.actions
        for output in action.outputs.to_list()
        if output.extension == "dia"
    ]
    transitive = [
        dep[_DiagnosticsInfo].files
        for name in _ATTRIBUTES
        for dep in getattr(ctx.rule.attr, name, [])
        if _DiagnosticsInfo in dep
    ]
    files = depset(direct, transitive = transitive)
    return [
        _DiagnosticsInfo(files = files),
        OutputGroupInfo(diagnostics = files),
    ]

diagnostics = aspect(
    implementation = _diagnostics_impl,
    attr_aspects = _ATTRIBUTES,
)
```

Request the aspect's output group to build and retrieve the collected files:

```sh
bazel build //path/to:target \
  --features=swift.serialized_diagnostics_file \
  --aspects=//tools:diagnostics.bzl%diagnostics \
  --output_groups=+diagnostics
```

Extend the aspect's traversal attributes for the rules in your dependency graph,
such as application bundles or compiler plugins. To also enable diagnostics for
Swift tools built in the execution configuration, pass
`--host_features=swift.serialized_diagnostics_file`.
