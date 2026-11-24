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

# The characters allowed in `tool`.
_TOOL_CHARS = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-"
)

def _bat_escape(value, description):
    """Escapes `value` for use inside a double-quoted batch `set` value.

    Fails the build if `value` contains a character that cannot be escaped
    there: a double quote, a carriage return or a newline.

    Args:
        value: The value to escape.
        description: What the value is, for the error message.

    Returns:
        `value` with `%` doubled.
    """
    for char, name in [
        ("\"", "a double quote"),
        ("\r", "a carriage return"),
        ("\n", "a newline"),
    ]:
        if char in value:
            fail(
                ("{} contains {}, which cannot be escaped in a Windows " +
                 "batch file: {}").format(description, name, repr(value)),
            )
    return value.replace("%", "%%")

def _bat_string_tool_path(swift_string, tool, suffix):
    """Returns the Windows path of `tool` for a `string` Swift driver.

    Args:
        swift_string: The driver: a bare name or a path, with the suffix.
        tool: The name of the tool to run.
        suffix: The toolchain's `tool_executable_suffix`.

    Returns:
        The tool to run, with backslashes, or `""` if there is no driver.
    """
    if not swift_string:
        return ""
    driver = swift_string.replace("/", "\\")
    if tool == "swift":
        return driver
    if "\\" not in driver:
        # A bare name, found on `PATH`.
        return tool + suffix
    return "{}\\{}{}".format(driver.rpartition("\\")[0], tool, suffix)

def _swift_toolchain_tool_impl(ctx):
    tool = ctx.attr.tool
    if not tool or [char for char in tool.elems() if char not in _TOOL_CHARS]:
        fail(
            "`tool` must be the bare name of a toolchain tool, such as " +
            "`swift-format`, made of the characters `A-Z`, `a-z`, `0-9`, " +
            "`.`, `_`, `+` and `-`; got '{}'.".format(tool),
        )

    swift_toolchain = get_swift_toolchain(ctx)
    multitool = getattr(swift_toolchain, "swift_multitool", None)
    if not multitool:
        fail(
            "The resolved Swift toolchain does not provide a `swift` " +
            "driver; `swift_toolchain_tool` cannot be used with it.",
        )
    suffix = getattr(multitool, "tool_executable_suffix", "") or ""

    executable = multitool.executable
    runfiles_files = list(multitool.files)
    if type(executable) == "File":
        swift_rlocationpath = _rlocationpath(ctx, executable)
        swift_string = ""
        runfiles_files.append(executable)
    else:
        swift_rlocationpath = ""
        swift_string = executable or ""

    # Skip Bazel placeholders (e.g. `__BAZEL_XCODE_SDKROOT__`) that only the
    # worker knows how to fill in.
    env = [
        (key, value)
        for key, value in sorted(multitool.env.items())
        if value != None and "__BAZEL_" not in value
    ]

    is_windows = ctx.target_platform_has_constraint(
        ctx.attr._windows_os_constraint[platform_common.ConstraintValueInfo],
    )
    if is_windows:
        script = ctx.actions.declare_file(ctx.label.name + ".bat")
        template = ctx.file._bat_template
        substitutions = {
            "%env_exports%": "\n".join([
                'set "{}={}"'.format(
                    _bat_escape(key, "A toolchain environment variable name"),
                    _bat_escape(
                        value,
                        "The toolchain environment variable `{}`".format(key),
                    ),
                )
                for key, value in env
            ]),
            "%swift_args%": " ".join([
                '"{}"'.format(_bat_escape(arg, "A Swift driver argument"))
                for arg in multitool.args
            ]),
            "%swift_rlocationpath%": _bat_escape(
                swift_rlocationpath,
                "The runfiles path of the Swift driver",
            ),
            "%string_tool_path%": _bat_escape(
                _bat_string_tool_path(swift_string, tool, suffix),
                "The path of the tool",
            ),
            "%tool%": _bat_escape(tool, "`tool`"),
            "%tool_executable_suffix%": _bat_escape(
                suffix,
                "The toolchain's `tool_executable_suffix`",
            ),
        }
        runfiles = ctx.runfiles(files = runfiles_files)
    else:
        xcode_locator = ctx.file._xcode_locator
        runfiles_files.append(xcode_locator)
        script = ctx.actions.declare_file(ctx.label.name)
        template = ctx.file._sh_template
        substitutions = {
            "%env_exports%": "\n".join([
                "export {}={}".format(key, shell.quote(value))
                for key, value in env
            ]),
            "%swift_args%": " ".join([
                shell.quote(arg)
                for arg in multitool.args
            ]),
            "%swift_rlocationpath%": shell.quote(swift_rlocationpath),
            "%swift_string%": shell.quote(swift_string),
            "%tool%": shell.quote(tool),
            "%tool_executable_suffix%": shell.quote(suffix),
            "%xcode_locator_rlocationpath%": shell.quote(
                _rlocationpath(ctx, xcode_locator),
            ),
        }
        runfiles = ctx.runfiles(files = runfiles_files).merge(
            ctx.attr._runfiles_lib[DefaultInfo].default_runfiles,
        )

    ctx.actions.expand_template(
        template = template,
        output = script,
        substitutions = substitutions,
        is_executable = True,
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

It must be a bare tool name made of the characters `A-Z`, `a-z`, `0-9`, `.`,
`_`, `+` and `-`; any other value, including an empty one, fails the build.
""",
        ),
        "_bat_template": attr.label(
            allow_single_file = True,
            default = Label("//swift/internal:swift_toolchain_tool.bat.tpl"),
        ),
        "_runfiles_lib": attr.label(
            default = Label("@bazel_tools//tools/bash/runfiles"),
        ),
        "_sh_template": attr.label(
            allow_single_file = True,
            default = Label("//swift/internal:swift_toolchain_tool.sh.tpl"),
        ),
        "_windows_os_constraint": attr.label(
            default = Label("@platforms//os:windows"),
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

The output is a bash script, or a `.bat` file when the target platform is
Windows. It runs the requested tool from the same toolchain that the Swift
build rules use (Xcode on macOS, or the configured swift.org toolchain on Linux
and Windows), exports the environment that the toolchain requires, and forwards
all of its arguments to the tool. This lets other rules run, for example,
`swift package dump-package` without depending on whatever `swift` is on
`PATH`.

On Windows, the `.bat` file forwards its arguments with `%*`, so cmd.exe parses
them again: callers must quote any argument that contains `&`, `|`, `<`, `>` or
`^`.

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
