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
    "//test/rules:provider_test.bzl",
    "make_provider_test_rule",
)

visibility("private")

_EXTRA_TOOLCHAINS = "//command_line_option:extra_toolchains"

_FIXTURES = "//test/fixtures/swift_toolchain_tool"

_FIXTURE_DRIVER = "test/fixtures/swift_toolchain_tool/bin/swift"

# Points the toolchain at a `File` driver. Xcode (and autoconfigured Linux)
# toolchains honor it; the hermetic standalone toolchain ignores it and keeps
# its own `usr/bin/swift`.
_CUSTOM_DRIVER_CONFIG = {
    str(Label("//swift:default_swift_executable")): str(
        Label("//test/fixtures/swift_toolchain_tool:bin/swift"),
    ),
}

def _template_substitutions(env, target):
    """Returns the substitutions of the action that writes the script.

    Args:
        env: The analysis test environment.
        target: The `swift_toolchain_tool` target under test.

    Returns:
        The substitutions `dict`, or `None` after logging a failure.
    """
    executable = target[DefaultInfo].files_to_run.executable
    if not executable:
        unittest.fail(env, "Expected {} to be executable.".format(
            target.label,
        ))
        return None

    asserts.equals(env, target.label.name, executable.basename)

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
    return template_actions[0].substitutions

def _script_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    substitutions = _template_substitutions(env, target)
    if substitutions == None:
        return analysistest.end(env)

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

_custom_driver_script_test = _make_script_test(_CUSTOM_DRIVER_CONFIG)

_FILE_DRIVER_CONFIG = _CUSTOM_DRIVER_CONFIG | {
    _EXTRA_TOOLCHAINS: ["{}:file_driver_toolchain".format(_FIXTURES)],
}

_file_driver_script_test = _make_script_test(_FILE_DRIVER_CONFIG)

_string_driver_script_test = _make_script_test({
    _EXTRA_TOOLCHAINS: ["{}:string_driver_toolchain".format(_FIXTURES)],
})

_xcode_custom_toolchain_script_test = _make_script_test({
    "//command_line_option:action_env": ["TOOLCHAINS=com.example.swift"],
})

_file_driver_provider_test = make_provider_test_rule(
    config_settings = _FILE_DRIVER_CONFIG,
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

_custom_driver_multitool_test = analysistest.make(
    _multitool_test_impl,
    attrs = {
        "expected_args": attr.string_list(),
        "expected_executable_suffix": attr.string(mandatory = True),
    },
    config_settings = _CUSTOM_DRIVER_CONFIG,
)

def swift_toolchain_tool_test_suite(name, tags = []):
    """Test suite for `swift_toolchain_tool`.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    _script_test(
        name = "{}_default_tool_script".format(name),
        expected_substitutions = {"%tool%": shell.quote("swift")},
        substitutions_contain = {
            "%xcode_locator_rlocationpath%": ["tools/osx/xcode-locator"],
        },
        tags = all_tags,
        target_under_test = "{}:swift".format(_FIXTURES),
    )

    _script_test(
        name = "{}_custom_tool_script".format(name),
        expected_substitutions = {"%tool%": shell.quote("swift-format")},
        tags = all_tags,
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

    native.test_suite(
        name = name,
        tags = all_tags,
    )
