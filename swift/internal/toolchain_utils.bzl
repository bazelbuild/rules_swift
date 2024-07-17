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

SWIFT_TOOLCHAIN_TYPE = "@build_bazel_rules_swift//toolchains:toolchain_type"

def get_swift_toolchain(ctx, attr = "_toolchain"):
    """Gets the Swift toolchain associated with the rule or aspect.

    Args:
        ctx: The rule or aspect context.
        attr: The name of the attribute on the calling rule or aspect that
            should be used to retrieve the toolchain if it is not provided by
            the `toolchains` argument of the rule/aspect. Note that this is only
            supported for legacy/migration purposes and will be removed once
            migration to toolchains is complete.

    Returns:
        A `SwiftToolchainInfo` provider.
    """
    if SWIFT_TOOLCHAIN_TYPE in ctx.toolchains:
        return ctx.toolchains[SWIFT_TOOLCHAIN_TYPE].swift_toolchain

    # TODO(b/205018581): Delete this code path when migration to the new
    # toolchain APIs is complete.
    toolchain_target = getattr(ctx.attr, attr, None)
    if toolchain_target and platform_common.ToolchainInfo in toolchain_target:
        return toolchain_target[platform_common.ToolchainInfo].swift_toolchain

    fail("To use `swift_common.get_toolchain`, you must declare the " +
         "toolchain in your rule using " +
         "`toolchains = swift_common.use_toolchain()`.")

def use_swift_toolchain():
    """Returns a list of toolchain types needed to use the Swift toolchain.

    This function returns a list so that it can be easily composed with other
    toolchains if necessary. For example, a rule with multiple toolchain
    dependencies could write:

    ```
    toolchains = swift_common.use_toolchain() + [other toolchains...]
    ```

    Returns:
        A list of toolchain types that should be passed to `rule()` or
        `aspect()`.
    """

    # TODO(b/205018581): Intentionally empty for now so that rule definitions
    # can reference the function while still being a no-op. A future change will
    # add the toolchain type to this list to enable toolchain resolution.
    return []
