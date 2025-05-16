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

"""Helpers used to depend on and access the Swift toolchain."""

load(
    "@rules_cc//cc:find_cc_toolchain.bzl",
    "find_cc_toolchain",
    "use_cc_toolchain",
)

visibility([
    "@build_bazel_rules_swift//swift/...",
])

SWIFT_TOOLCHAIN_TYPE = "@build_bazel_rules_swift//toolchains:toolchain_type"

def find_all_toolchains(
        ctx,
        *,
        exec_group = None,
        mandatory = True,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE):
    """Finds all toolchains required to build Swift code.

    The Swift build APIs require the C++ toolchain to link libraries and
    binaries, so this function finds both and returns them in a convenient
    structure that should be passed to the other build APIs.

    Args:
        ctx: The rule or aspect context.
        exec_group: The name of the execution group that contains the Swift
            toolchain. If this is provided and the toolchain is not declared in
            that execution group, it will be looked up from `ctx` as a fallback
            instead. If this argument is `None` (the default), then the Swift
            toolchain will only be looked up from `ctx.`
        mandatory: If `False`, this function will return `None` instead of
            failing if no toolchain is found. Defaults to `True`.
        toolchain_type: The Swift toolchain type to use. Defaults to the
            standard Swift toolchain type.

    Returns:
        A `struct` containing the following fields:

        *   `cc`: The `cc_common.CcToolchainInfo` provider representing the C++
            toolchain, or `None` if the C++ toolchain was not found as is not
            mandatory.
        *   `swift`: The `SwiftToolchainInfo` provider representing the Swift
            toolchain, or `None` if the Swift toolchain was not found and is not
            mandatory.
    """
    swift_toolchain = None

    if exec_group:
        group = ctx.exec_groups[exec_group]
        if group and toolchain_type in group.toolchains:
            swift_toolchain = group.toolchains[toolchain_type].swift_toolchain

    if (
        not swift_toolchain and
        toolchain_type in ctx.toolchains and
        ctx.toolchains[toolchain_type]
    ):
        swift_toolchain = ctx.toolchains[toolchain_type].swift_toolchain

    if not swift_toolchain and mandatory:
        fail("To use `swift_common.find_all_toolchains()`, you must declare " +
             "the toolchains in your rule using " +
             "`toolchains = swift_common.use_all_toolchains()`.")

    return struct(
        cc = find_cc_toolchain(ctx, mandatory = mandatory),
        swift = swift_toolchain,
    )

def use_all_toolchains(
        *,
        mandatory = True,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE):
    """Returns a list of toolchain types required to build Swift code.

    The Swift build APIs require the C++ toolchain to link libraries and
    binaries, so this function requests both for convenience.

    This function returns a list so that it can be easily composed with other
    toolchains if necessary. For example, a rule that requires toolchains other
    than Swift and C++ could write:

    ```
    toolchains = swift_common.use_all_toolchains() + [other toolchains...]
    ```

    Args:
        mandatory: Whether or not it should be an error if the toolchain cannot
            be resolved. Defaults to True.
        toolchain_type: The Swift toolchain type to use. Defaults to the
            standard Swift toolchain type.

    Returns:
        A list of
        [toolchain types](https://bazel.build/rules/lib/builtins/toolchain_type.html)
        that should be passed to `rule()`, `aspect()`, or `exec_group()`.
    """
    return use_cc_toolchain() + [
        config_common.toolchain_type(
            toolchain_type,
            mandatory = mandatory,
        ),
    ]
