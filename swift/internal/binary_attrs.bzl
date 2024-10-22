# Copyright 2024 The Bazel Authors. All rights reserved.
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

"""Common attributes used by rules that define Swift binary targets."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//swift:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(":attrs.bzl", "swift_compilation_attrs")

_MALLOC_DOCSTRING = """\
Override the default dependency on `malloc`.

By default, Swift binaries are linked against `@bazel_tools//tools/cpp:malloc"`,
which is an empty library and the resulting binary will use libc's `malloc`.
This label must refer to a `cc_library` rule.
"""

def binary_rule_attrs(
        *,
        additional_deps_aspects = [],
        additional_deps_providers = [],
        stamp_default):
    """Returns attributes common to both `swift_binary` and `swift_test`.

    Args:
        additional_deps_aspects: A list of additional aspects that should be
            applied to the `deps` attribute of the rule.
        additional_deps_providers: A list of lists representing additional
            providers that should be allowed by the `deps` attribute of the
            rule.
        stamp_default: The default value of the `stamp` attribute.

    Returns:
        A `dict` of attributes for a binary or test rule.
    """
    return dicts.add(
        swift_compilation_attrs(
            additional_deps_aspects = [
                swift_clang_module_aspect,
            ] + additional_deps_aspects,
            additional_deps_providers = additional_deps_providers,
            requires_srcs = False,
        ),
        {
            "linkopts": attr.string_list(
                doc = """\
Additional linker options that should be passed to `clang`. These strings are
subject to `$(location ...)` expansion.
""",
                mandatory = False,
            ),
            "malloc": attr.label(
                default = Label("@bazel_tools//tools/cpp:malloc"),
                doc = _MALLOC_DOCSTRING,
                mandatory = False,
                providers = [[CcInfo]],
            ),
            "stamp": attr.int(
                default = stamp_default,
                doc = """\
Enable or disable link stamping; that is, whether to encode build information
into the binary. Possible values are:

* `stamp = 1`: Stamp the build information into the binary. Stamped binaries are
  only rebuilt when their dependencies change. Use this if there are tests that
  depend on the build information.

* `stamp = 0`: Always replace build information by constant values. This gives
  good build result caching.

* `stamp = -1`: Embedding of build information is controlled by the
  `--[no]stamp` flag.
""",
                mandatory = False,
            ),
            # Do not add references; temporary attribute for C++ toolchain
            # Starlark migration.
            "_cc_toolchain": attr.label(
                default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            ),
            # A late-bound attribute denoting the value of the `--custom_malloc`
            # command line flag (or None if the flag is not provided).
            "_custom_malloc": attr.label(
                default = configuration_field(
                    fragment = "cpp",
                    name = "custom_malloc",
                ),
                providers = [[CcInfo]],
            ),
        },
    )
