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

"""Tests for `swift_toolchain_tool`."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load(
    "//test/fixtures/swift_toolchain_tool:swift_multitool_info.bzl",
    "SwiftMultitoolTestInfo",
)
load(
    "//test/rules:analysis_failure_test.bzl",
    "analysis_failure_test",
    "make_analysis_failure_test_rule",
)
load(
    "//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

visibility("private")

_EXTRA_TOOLCHAINS = "//command_line_option:extra_toolchains"

_PLATFORMS = "//command_line_option:platforms"

_FIXTURES = "//test/fixtures/swift_toolchain_tool"

_FIXTURE_DRIVER = "test/fixtures/swift_toolchain_tool/bin/swift"

_HERMETIC_BIN = "test/fixtures/swift_toolchain_tool/hermetic/usr/bin"

# Points the toolchain at a `File` driver. Xcode (and autoconfigured Linux)
# toolchains honor it; the hermetic standalone toolchain ignores it and keeps
# its own `usr/bin/swift`.
_CUSTOM_DRIVER_CONFIG = {
    str(Label("//swift:default_swift_executable")): str(
        Label("//test/fixtures/swift_toolchain_tool:bin/swift"),
    ),
}

def _template_action(env, target, extension = ""):
    """Returns the action that writes the script.

    Args:
        env: The analysis test environment.
        target: The `swift_toolchain_tool` target under test.
        extension: The expected extension of the script, e.g. `.bat`.

    Returns:
        The `TemplateExpand` action, or `None` after logging a failure.
    """
    executable = target[DefaultInfo].files_to_run.executable
    if not executable:
        unittest.fail(env, "Expected {} to be executable.".format(
            target.label,
        ))
        return None

    asserts.equals(env, target.label.name + extension, executable.basename)

    template_actions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "TemplateExpand" and
           executable in action.outputs.to_list()
    ]
    if len(template_actions) != 1:
        unittest.fail(
            env,
            "Expected one TemplateExpand action creating {}, found {}.".format(
                executable.short_path,
                len(template_actions),
            ),
        )
        return None
    return template_actions[0]

def _script_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    action = _template_action(env, target)
    if action == None:
        return analysistest.end(env)
    substitutions = action.substitutions

    for key, expected in ctx.attr.expected_substitutions.items():
        asserts.equals(
            env,
            expected,
            substitutions.get(key),
            "Unexpected value for '{}'.".format(key),
        )

    for key, needles in ctx.attr.substitutions_contain.items():
        value = substitutions.get(key, "")
        for needle in needles:
            asserts.true(
                env,
                needle in value,
                "Expected '{}' to contain '{}', got '{}'.".format(
                    key,
                    needle,
                    value,
                ),
            )

    for key, needles in ctx.attr.substitutions_do_not_contain.items():
        value = substitutions.get(key, "")
        for needle in needles:
            asserts.false(
                env,
                needle in value,
                "Expected '{}' not to contain '{}', got '{}'.".format(
                    key,
                    needle,
                    value,
                ),
            )

    return analysistest.end(env)

_SCRIPT_TEST_ATTRS = {
    "expected_substitutions": attr.string_dict(
        doc = "Template substitutions that must have exactly these values.",
    ),
    "substitutions_contain": attr.string_list_dict(
        doc = "Template substitutions that must contain each of the strings.",
    ),
    "substitutions_do_not_contain": attr.string_list_dict(
        doc = "Template substitutions that must not contain the strings.",
    ),
}

def _make_script_test(config_settings = {}):
    return analysistest.make(
        _script_test_impl,
        attrs = _SCRIPT_TEST_ATTRS,
        config_settings = config_settings,
    )

_script_test = _make_script_test()

def _on_platform(os, toolchain, config = {}):
    """Returns `config` that targets a fixture platform with `toolchain`.

    Args:
        os: The OS of the fixture platform, `linux` or `windows`.
        toolchain: The name of the fixture Swift toolchain to select.
        config: Other settings to add.

    Returns:
        A `dict` of `config_settings`.
    """
    fixture = lambda name: str(Label("{}:{}".format(_FIXTURES, name)))
    return config | {
        _EXTRA_TOOLCHAINS: [
            fixture("{}_cc_toolchain".format(os)),
            fixture(toolchain),
        ],
        _PLATFORMS: [fixture("{}_x86_64".format(os))],
    }

_custom_driver_script_test = _make_script_test(_CUSTOM_DRIVER_CONFIG)

_FILE_DRIVER_CONFIG = _on_platform(
    "linux",
    "file_driver_toolchain",
    _CUSTOM_DRIVER_CONFIG,
)

_file_driver_script_test = _make_script_test(_FILE_DRIVER_CONFIG)

_ATTR_FILE_DRIVER_CONFIG = _on_platform(
    "linux",
    "attr_file_driver_toolchain",
)

_attr_file_driver_script_test = _make_script_test(_ATTR_FILE_DRIVER_CONFIG)

_string_driver_script_test = _make_script_test(
    _on_platform("linux", "string_driver_toolchain"),
)

_relative_root_script_test = _make_script_test(
    _on_platform("linux", "relative_root_toolchain"),
)

_HERMETIC_CONFIG = _on_platform("linux", "hermetic_swift_toolchain")

_HERMETIC_DRIVER_ONLY_CONFIG = _on_platform(
    "linux",
    "hermetic_driver_only_toolchain",
)

_xcode_custom_toolchain_script_test = _make_script_test({
    "//command_line_option:action_env": ["TOOLCHAINS=com.example.swift"],
})

def _bat_script_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    action = _template_action(env, target, extension = ".bat")
    if action == None:
        return analysistest.end(env)
    content = action.content
    if content == None:
        unittest.fail(env, "Expected the script content at analysis time.")
        return analysistest.end(env)

    lines = content.split("\n")
    for line in ctx.attr.contains_lines:
        asserts.true(
            env,
            line in lines,
            "Expected the script to contain the line '{}'.".format(line),
        )
    for needle in ctx.attr.does_not_contain:
        asserts.false(
            env,
            needle in content,
            "Expected the script not to contain '{}'.".format(needle),
        )

    return analysistest.end(env)

def _make_bat_script_test(config_settings):
    return analysistest.make(
        _bat_script_test_impl,
        attrs = {
            "contains_lines": attr.string_list(
                doc = "Lines that the rendered script must contain.",
            ),
            "does_not_contain": attr.string_list(
                doc = "Strings that the rendered script must not contain.",
            ),
        },
        config_settings = config_settings,
    )

_windows_string_driver_bat_test = _make_bat_script_test(
    _on_platform("windows", "windows_string_driver_toolchain"),
)

_windows_file_driver_bat_test = _make_bat_script_test(
    _on_platform("windows", "windows_file_driver_toolchain"),
)

_windows_quoted_env_failure_test = make_analysis_failure_test_rule(
    _on_platform("windows", "windows_quoted_env_toolchain"),
)

_file_driver_provider_test = make_provider_test_rule(
    config_settings = _FILE_DRIVER_CONFIG,
)

_hermetic_provider_test = make_provider_test_rule(
    config_settings = _HERMETIC_CONFIG,
)

def _multitool_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    multitool = target[SwiftMultitoolTestInfo].swift_multitool
    if not multitool:
        unittest.fail(env, "Expected the toolchain to have a swift_multitool.")
        return analysistest.end(env)

    executable = multitool.executable
    if type(executable) != "File":
        unittest.fail(
            env,
            "Expected swift_multitool.executable to be a File, got {}.".format(
                repr(executable),
            ),
        )
        return analysistest.end(env)

    asserts.true(
        env,
        executable.short_path.endswith(ctx.attr.expected_executable_suffix),
        "Expected swift_multitool.executable to end with '{}', got '{}'.".format(
            ctx.attr.expected_executable_suffix,
            executable.short_path,
        ),
    )
    asserts.equals(env, ctx.attr.expected_args, multitool.args)
    asserts.equals(
        env,
        ctx.attr.expected_tool_executable_suffix,
        multitool.tool_executable_suffix,
    )
    asserts.true(
        env,
        executable in multitool.files,
        "Expected swift_multitool.files to contain the executable.",
    )
    asserts.false(
        env,
        "TOOLCHAIN_PATH" in multitool.env,
        "swift_multitool.env must not contain TOOLCHAIN_PATH.",
    )

    return analysistest.end(env)

def _make_multitool_test(config_settings):
    return analysistest.make(
        _multitool_test_impl,
        attrs = {
            "expected_args": attr.string_list(),
            "expected_executable_suffix": attr.string(mandatory = True),
            "expected_tool_executable_suffix": attr.string(default = ""),
        },
        config_settings = config_settings,
    )

_custom_driver_multitool_test = _make_multitool_test(_CUSTOM_DRIVER_CONFIG)

_attr_file_driver_multitool_test = _make_multitool_test(
    _ATTR_FILE_DRIVER_CONFIG,
)

_hermetic_multitool_test = _make_multitool_test(_HERMETIC_CONFIG)

_hermetic_driver_only_multitool_test = _make_multitool_test(
    _HERMETIC_DRIVER_ONLY_CONFIG,
)

def swift_toolchain_tool_test_suite(name, tags = []):
    """Test suite for `swift_toolchain_tool`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Tests of the host toolchain's bash script; Windows hosts get a `.bat`.
    not_windows = select({
        "@platforms//os:windows": ["@platforms//:incompatible"],
        "//conditions:default": [],
    })

    _script_test(
        name = "{}_default_tool_script".format(name),
        expected_substitutions = {"%tool%": shell.quote("swift")},
        substitutions_contain = {
            "%xcode_locator_rlocationpath%": ["tools/osx/xcode-locator"],
        },
        tags = all_tags,
        target_compatible_with = not_windows,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    _script_test(
        name = "{}_custom_tool_script".format(name),
        expected_substitutions = {"%tool%": shell.quote("swift-format")},
        tags = all_tags,
        target_compatible_with = not_windows,
        target_under_test = "{}:swift_format".format(_FIXTURES),
    )

    # A `File` driver is run from the runfiles with `--driver-mode=swift`.
    # Placeholder values are dropped and the rest of the environment, including
    # `TOOLCHAINS`, is exported.
    _file_driver_script_test(
        name = "{}_file_driver_script".format(name),
        expected_substitutions = {
            "%swift_args%": shell.quote("--driver-mode=swift"),
            "%swift_string%": shell.quote(""),
        },
        substitutions_contain = {
            "%env_exports%": [
                "export FOO={}".format(shell.quote("bar baz")),
                "export TOOLCHAINS={}".format(
                    shell.quote("com.example.swift"),
                ),
            ],
            "%swift_rlocationpath%": [_FIXTURE_DRIVER],
        },
        substitutions_do_not_contain = {
            "%env_exports%": ["__BAZEL_", "SDKROOT", "TOOLCHAIN_PATH"],
        },
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    _file_driver_provider_test(
        name = "{}_file_driver_runfiles".format(name),
        expected_files = [
            _FIXTURE_DRIVER,
            "tools/osx/xcode-locator",
            "*",
        ],
        field = "default_runfiles.files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # A driver set with the toolchain's `swift_executable` attribute is run
    # from the runfiles with `--driver-mode=swift`.
    _attr_file_driver_script_test(
        name = "{}_attr_file_driver_script".format(name),
        expected_substitutions = {
            "%swift_args%": shell.quote("--driver-mode=swift"),
            "%swift_string%": shell.quote(""),
        },
        substitutions_contain = {
            "%swift_rlocationpath%": [_FIXTURE_DRIVER],
        },
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    _attr_file_driver_multitool_test(
        name = "{}_attr_file_driver_multitool".format(name),
        expected_args = ["--driver-mode=swift"],
        expected_executable_suffix = _FIXTURE_DRIVER,
        tags = all_tags,
        target_under_test = "{}:multitool_info".format(_FIXTURES),
    )

    # A driver found on the system is run by path, without driver flags.
    _string_driver_script_test(
        name = "{}_string_driver_script".format(name),
        expected_substitutions = {
            "%swift_args%": "",
            "%swift_rlocationpath%": shell.quote(""),
            "%swift_string%": shell.quote("/opt/swift/usr/bin/swift"),
        },
        substitutions_do_not_contain = {
            "%env_exports%": ["__BAZEL_", "TOOLCHAIN_PATH"],
        },
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # A relative toolchain root is relative to the execution root, so `swift`
    # is found on `PATH` instead.
    _relative_root_script_test(
        name = "{}_relative_root_script".format(name),
        expected_substitutions = {
            "%swift_args%": "",
            "%swift_rlocationpath%": shell.quote(""),
            "%swift_string%": shell.quote("swift"),
        },
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # A hermetic toolchain runs its `swift` multi-tool as is, with its
    # `swift_runfiles` in the runfiles.
    _hermetic_multitool_test(
        name = "{}_hermetic_multitool".format(name),
        expected_args = [],
        expected_executable_suffix = "{}/swift".format(_HERMETIC_BIN),
        tags = all_tags,
        target_under_test = "{}:multitool_info".format(_FIXTURES),
    )

    _hermetic_provider_test(
        name = "{}_hermetic_runfiles".format(name),
        expected_files = [
            "{}/swift".format(_HERMETIC_BIN),
            "{}/swift-package".format(_HERMETIC_BIN),
            "*",
        ],
        field = "default_runfiles.files",
        provider = "DefaultInfo",
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # A hermetic toolchain without a `swift` multi-tool runs its driver with
    # `--driver-mode=swift`.
    _hermetic_driver_only_multitool_test(
        name = "{}_hermetic_driver_only_multitool".format(name),
        expected_args = ["--driver-mode=swift"],
        expected_executable_suffix = "{}/swiftc".format(_HERMETIC_BIN),
        tags = all_tags,
        target_under_test = "{}:multitool_info".format(_FIXTURES),
    )

    # `tool` must be a bare name.
    analysis_failure_test(
        name = "{}_invalid_tool".format(name),
        expected_message = "`tool` must be the bare name of a toolchain tool",
        tags = all_tags,
        target_under_test = "{}:invalid_tool".format(_FIXTURES),
    )

    # The host toolchain under `--default_swift_executable`. Xcode runs the
    # custom driver in `swift` mode; the hermetic Linux toolchain ignores the
    # flag and runs its own `usr/bin/swift`.
    _custom_driver_script_test(
        name = "{}_custom_driver_script".format(name),
        expected_substitutions = select({
            "@platforms//os:macos": {
                "%swift_args%": shell.quote("--driver-mode=swift"),
                "%swift_string%": shell.quote(""),
            },
            "//conditions:default": {
                "%swift_args%": "",
                "%swift_string%": shell.quote(""),
            },
        }),
        substitutions_contain = select({
            "@platforms//os:macos": {
                "%swift_rlocationpath%": [_FIXTURE_DRIVER],
            },
            "//conditions:default": {
                "%swift_rlocationpath%": ["usr/bin/swift"],
            },
        }),
        substitutions_do_not_contain = {
            "%env_exports%": ["__BAZEL_", "TOOLCHAIN_PATH"],
        },
        tags = all_tags,
        target_compatible_with = not_windows,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    _custom_driver_multitool_test(
        name = "{}_custom_driver_multitool".format(name),
        expected_args = select({
            "@platforms//os:macos": ["--driver-mode=swift"],
            "//conditions:default": [],
        }),
        expected_executable_suffix = select({
            "@platforms//os:macos": _FIXTURE_DRIVER,
            "//conditions:default": "usr/bin/swift",
        }),
        tags = all_tags,
        target_compatible_with = not_windows,
        target_under_test = "{}:multitool_info".format(_FIXTURES),
    )

    # Xcode exports the `TOOLCHAINS` that selects a custom Swift toolchain.
    _xcode_custom_toolchain_script_test(
        name = "{}_xcode_toolchains_env_script".format(name),
        substitutions_contain = {
            "%env_exports%": [
                "export TOOLCHAINS={}".format(
                    shell.quote("com.example.swift"),
                ),
                "export XCODE_VERSION_OVERRIDE=",
            ],
        },
        substitutions_do_not_contain = {
            "%env_exports%": ["__BAZEL_"],
        },
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # On Windows, the script is a `.bat` that runs the toolchain's `.exe`
    # tools and sets the environment with `%` escaped. Placeholders are
    # dropped, and `SDKROOT` is set to the toolchain's SDK.
    _windows_string_driver_bat_test(
        name = "{}_windows_string_driver_bat".format(name),
        contains_lines = [
            'set "TOOL_NAME=swift"',
            'set "TOOL_SUFFIX=.exe"',
            'set "DRIVER_RLOCATIONPATH="',
            'set "TOOL_PATH=C:\\Swift\\usr\\bin\\swift.exe"',
            "set DRIVER_ARGS=",
            'set "FOO=100%% done"',
            'set "Path=C:\\Swift\\usr\\bin;C:\\Windows"',
            'set "ProgramData=C:\\ProgramData"',
            'set "SDKROOT=C:/Swift/Platforms/Windows.platform/Developer/SDKs/Windows.sdk"',
            "exit /b %ERRORLEVEL%",
        ],
        does_not_contain = ["__BAZEL_", "export "],
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # Other tools are the driver's `.exe` siblings.
    _windows_string_driver_bat_test(
        name = "{}_windows_string_driver_sibling_bat".format(name),
        contains_lines = [
            'set "TOOL_NAME=swift-format"',
            'set "TOOL_PATH=C:\\Swift\\usr\\bin\\swift-format.exe"',
        ],
        tags = all_tags,
        target_under_test = "{}:swift_format".format(_FIXTURES),
    )

    # A `File` driver is found through the runfiles manifest from the
    # environment or next to the script, and run with `--driver-mode=swift`.
    _windows_file_driver_bat_test(
        name = "{}_windows_file_driver_bat".format(name),
        contains_lines = [
            'set "TOOL_NAME=swift"',
            'set "DRIVER_RLOCATIONPATH=_main/{}"'.format(_FIXTURE_DRIVER),
            'set "TOOL_PATH="',
            'set DRIVER_ARGS="--driver-mode=swift"',
            "if not \"%MANIFEST%\"==\"\" for /f \"usebackq tokens=1,*\" " +
            "%%A in (`findstr /b /l /c:\"%DRIVER_RLOCATIONPATH% \" " +
            "\"%MANIFEST%\"`) do if not defined DRIVER set \"DRIVER=%%B\"",
            "if not \"%DRIVER_RLOCATIONPATH%\"==\"\" if not defined DRIVER " +
            "if exist \"%~dpn0.bat.runfiles_manifest\" for /f " +
            "\"usebackq tokens=1,*\" %%A in (`findstr /b /l " +
            "/c:\"%DRIVER_RLOCATIONPATH% \" " +
            "\"%~dpn0.bat.runfiles_manifest\"`) do if not defined DRIVER " +
            "set \"DRIVER=%%B\"",
        ],
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    # A double quote cannot be escaped in a `.bat` file.
    _windows_quoted_env_failure_test(
        name = "{}_windows_quoted_env".format(name),
        expected_message = (
            "The toolchain environment variable `FOO` contains a double quote"
        ),
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
