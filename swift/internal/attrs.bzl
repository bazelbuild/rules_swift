# Copyright 2018 The Bazel Authors. All rights reserved.
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

"""Common attributes used by multiple Swift build rules."""

load(":providers.bzl", "SwiftInfo")

def swift_common_rule_attrs(additional_deps_aspects = []):
    return {
        "data": attr.label_list(
            allow_files = True,
            doc = """\
The list of files needed by this target at runtime.

Files and targets named in the `data` attribute will appear in the `*.runfiles`
area of this target, if it has one. This may include data files needed by a
binary or library, or other programs needed by it.
""",
        ),
        "deps": swift_deps_attr(
            aspects = additional_deps_aspects,
            doc = """\
A list of targets that are dependencies of the target being built, which will be
linked into that target.

If the Swift toolchain supports implementation-only imports (`private_deps` on
`swift_library`), then targets in `deps` are treated as regular
(non-implementation-only) imports that are propagated both to their direct and
indirect (transitive) dependents.
""",
        ),
    }

def swift_deps_attr(doc, **kwargs):
    """Returns an attribute suitable for representing Swift rule dependencies.

    The returned attribute will be configured to accept targets that propagate
    `CcInfo`, `SwiftInfo`, or `apple_common.Objc` providers.

    Args:
        doc: A string containing a summary description of the purpose of the
            attribute. This string will be followed by additional text that
            lists the permitted kinds of targets that may go in this attribute.
        **kwargs: Additional arguments that are passed to `attr.label_list`
            unmodified.

    Returns:
        A rule attribute.
    """
    return attr.label_list(
        doc = doc + """\

Allowed kinds of dependencies are:

*   `swift_c_module`, `swift_import` and `swift_library` (or anything
    propagating `SwiftInfo`)
*   `cc_library` (or anything propagating `CcInfo`)

Additionally, on platforms that support Objective-C interop, `objc_library`
targets (or anything propagating the `apple_common.Objc` provider) are allowed
as dependencies. On platforms that do not support Objective-C interop (such as
Linux), those dependencies will be **ignored.**
""",
        providers = [
            [CcInfo],
            [SwiftInfo],
            [apple_common.Objc],
        ],
        **kwargs
    )

def swift_toolchain_driver_attrs():
    """Returns attributes used to attach custom drivers to toolchains.

    These attributes are useful for compiler development alongside Bazel. The
    public attribute (`swift_executable`) lets a custom driver be permanently
    associated with a particular toolchain instance. If not specified, the
    private default is associated with a command-line option that can be used to
    provide a custom driver at build time.

    Returns:
        A dictionary of attributes that should be added to a toolchain rule.
    """
    return {
        "swift_executable": attr.label(
            allow_single_file = True,
            cfg = "host",
            doc = """\
A replacement Swift driver executable.

If this is empty, the default Swift driver in the toolchain will be used.
Otherwise, this binary will be used and `--driver-mode` will be passed to ensure
that it is invoked in the correct mode (i.e., `swift`, `swiftc`,
`swift-autolink-extract`, etc.).
""",
        ),
        "_default_swift_executable": attr.label(
            allow_files = True,
            cfg = "host",
            default = Label(
                "@build_bazel_rules_swift//swift:default_swift_executable",
            ),
        ),
    }
