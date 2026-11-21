# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""A runnable wrapper around a tool from the resolved Swift toolchain."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    "//swift/internal:toolchain_utils.bzl",
    "get_swift_toolchain",
    "use_swift_toolchain",
)

def _rlocationpath(ctx, file):
    """Returns the runfiles library path of `file`."""
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(ctx.workspace_name, file.short_path)

def _swift_toolchain_tool_impl(ctx):
    tool = ctx.attr.tool
    if not tool or "/" in tool or "\\" in tool:
        fail(
            "`tool` must be the bare name of a toolchain tool, such as " +
            "`swift-format`, not empty or a path; got '{}'.".format(tool),
        )

    swift_toolchain = get_swift_toolchain(ctx)
    multitool = getattr(swift_toolchain, "swift_multitool", None)
    if not multitool:
        fail(
            "The resolved Swift toolchain does not provide a `swift` " +
            "driver; `swift_toolchain_tool` cannot be used with it.",
        )

    executable = multitool.executable
    runfiles_files = list(multitool.files)
    if type(executable) == "File":
        swift_rlocationpath = _rlocationpath(ctx, executable)
        swift_string = ""
        runfiles_files.append(executable)
    else:
        swift_rlocationpath = ""
        swift_string = executable or ""

    xcode_locator = ctx.file._xcode_locator
    runfiles_files.append(xcode_locator)

    env_exports = "\n".join([
        "export {}={}".format(key, shell.quote(value))
        for key, value in sorted(multitool.env.items())
        # Skip Bazel placeholders (e.g. `__BAZEL_XCODE_SDKROOT__`) that only
        # the worker knows how to fill in.
        if value != None and "__BAZEL_" not in value
    ])

    script = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = script,
        substitutions = {
            "%env_exports%": env_exports,
            "%swift_args%": " ".join([
                shell.quote(arg)
                for arg in multitool.args
            ]),
            "%swift_rlocationpath%": shell.quote(swift_rlocationpath),
            "%swift_string%": shell.quote(swift_string),
            "%tool%": shell.quote(tool),
            "%xcode_locator_rlocationpath%": shell.quote(
                _rlocationpath(ctx, xcode_locator),
            ),
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = runfiles_files).merge(
        ctx.attr._runfiles_lib[DefaultInfo].default_runfiles,
    )

    return [
        DefaultInfo(
            executable = script,
            files = depset([script]),
            runfiles = runfiles,
        ),
    ]

swift_toolchain_tool = rule(
    attrs = {
        "tool": attr.string(
            default = "swift",
            doc = """\
The name of the toolchain tool to run, such as `swift` (the default),
`swift-format`, or `swift-build`.

`swift` runs the toolchain's `swift` driver. Any other value runs the tool with
that name from the same directory as the driver for toolchains that provide one
(standalone swift.org toolchains), via `xcrun` for Xcode, or from `PATH`
otherwise.

It must be a bare tool name: an empty value or one that contains `/` or `\\`
fails the build.
""",
        ),
        "_runfiles_lib": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_template": attr.label(
            allow_single_file = True,
            default = Label("//swift/internal:swift_toolchain_tool.sh.tpl"),
        ),
        "_xcode_locator": attr.label(
            # Bazel's own locator; it is a stub that always fails on other
            # platforms, where the wrapper never runs it.
            allow_single_file = True,
            default = Label("@bazel_tools//tools/osx:xcode-locator-genrule"),
        ),
    },
    doc = """\
Creates an executable that runs a tool from the resolved Swift toolchain.

The generated script runs the requested tool from the same toolchain that the
Swift build rules use (Xcode on macOS, or the configured swift.org toolchain on
Linux), exports the environment that the toolchain requires, and forwards all
of its arguments to the tool. This lets other rules run, for example,
`swift package dump-package` without depending on whatever `swift` is on
`PATH`.

On macOS, the script runs the Xcode that Bazel selected (for example with
`--xcode_version`) by setting `DEVELOPER_DIR` to that Xcode, unless
`DEVELOPER_DIR` is already set.

The target can be run with `bazel run` or used as a tool by other rules. When
another rule uses it to run actions, depend on it with `cfg = "exec"` so that
the toolchain is resolved for the execution platform.

Example:

```build
load("@rules_swift//swift:swift_toolchain_tool.bzl", "swift_toolchain_tool")

swift_toolchain_tool(
    name = "swift",
)

swift_toolchain_tool(
    name = "swift_format",
    tool = "swift-format",
)
```

```shell
bazel run //:swift -- --version
```
""",
    executable = True,
    implementation = _swift_toolchain_tool_impl,
    toolchains = use_swift_toolchain(),
)
