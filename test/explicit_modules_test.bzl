# Copyright 2022 The Bazel Authors. All rights reserved.
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

"""Tests for explicit module compilation command line flags"""

load(
    "@build_bazel_rules_swift//test/rules:action_command_line_test.bzl",
    "make_action_command_line_test_rule",
)

explicit_modules_action_command_line_test = make_action_command_line_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_c_modules",
            "swift.emit_c_module",
            "swift.supports_system_module_flag",
        ],
    },
)

implicit_modules_action_command_line_test = make_action_command_line_test_rule()

def explicit_modules_test_suite(name):
    """Test suite for explicit clang module compilation.

    Args:
      name: the base name to be used in things created by this macro
    """

    # Verify that swift libraries compile with the specified module file from deps.
    explicit_modules_action_command_line_test(
        name = "{}_enabled_swift_side_test".format(name),
        expected_argv = [
            "-fmodule-file=SwiftShims",
            "-fno-implicit-module-maps",
            "-fno-implicit-modules",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/explicit_modules:simple",
        target_compatible_with = ["@platforms//os:macos"],
    )

    # Verify that the swift_c_module precompiles.
    explicit_modules_action_command_line_test(
        name = "{}_enabled_c_module_side".format(name),
        expected_argv = [
            "-fsystem-module",
            "-module-name SwiftShims",
            "-emit-pcm",
            "-fno-implicit-module-maps",
            "-fno-implicit-modules",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/explicit_modules:shims",
        target_compatible_with = ["@platforms//os:macos"],
    )

    # Verify that a swift_c_module with dependencies precompiles.
    explicit_modules_action_command_line_test(
        name = "{}_enabled_c_module_deps".format(name),
        expected_argv = [
            "-fsystem-module",
            "-fmodule-file=_Builtin_stddef_max_align_t",
            "-fmodule-map-file=__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/clang/include/module.modulemap",
            "-module-name Darwin",
            "-emit-pcm",
            "-fno-implicit-module-maps",
            "-fno-implicit-modules",
        ],
        mnemonic = "SwiftPrecompileCModule",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/explicit_modules:Darwin",
        target_compatible_with = ["@platforms//os:macos"],
    )

    # Verify that the default behavior isn't impacted.
    implicit_modules_action_command_line_test(
        name = "{}_disabled_test".format(name),
        not_expected_argv = [
            "-fmodule-file=SwiftShims",
            "-fno-implicit-module-maps",
            "-fno-implicit-modules",
        ],
        mnemonic = "SwiftCompile",
        tags = [name],
        target_under_test = "@build_bazel_rules_swift//test/fixtures/explicit_modules:simple",
    )

    native.test_suite(
        name = name,
        tags = [name],
    )
