# Copyright 2021 The Bazel Authors. All rights reserved.
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

"""Implementation of the `swift_interop_hint` rule."""

load(":swift_common.bzl", "swift_common")

def _swift_interop_hint_impl(ctx):
    # TODO(b/194733180): For now, this rule only supports interop via an
    # auto-derived module name or an explicit module name, but still using the
    # auto-generated module name. Add support for manual module maps and other
    # features, like APINotes, later.
    return swift_common.create_swift_interop_info(
        module_name = ctx.attr.module_name,
    )

swift_interop_hint = rule(
    attrs = {
        "module_name": attr.string(
            doc = """\
The name that will be used to import the hinted module into Swift.

If left unspecified, the module name will be computed based on the hinted
target's build label, by stripping the leading `//` and replacing `/`, `:`, and
other non-identifier characters with underscores.
""",
            mandatory = False,
        ),
    },
    doc = """\
Defines an aspect hint that associates non-Swift BUILD targets with additional
information required for them to be imported by Swift.

Some build rules, such as `objc_library`, support interoperability with Swift
simply by depending on them; a module map is generated automatically. This is
for convenience, because the common case is that most `objc_library` targets
contain code that is compatible (i.e., capable of being imported) by Swift.

For other rules, like `cc_library`, additional information must be provided to
indicate that a particular target is compatible with Swift. This is done using
the `aspect_hints` attribute and the `swift_interop_hint` rule.

#### Using the automatically derived module name (recommended)

If you want to import a non-Swift, non-Objective-C target into Swift using the
module name that is automatically derived from the BUILD label, there is no need
to declare an instance of `swift_interop_hint`. A canonical one that requests
module name derivation has been provided in
`@build_bazel_rules_swift//swift:auto_module`. Simply add it to the `aspect_hints` of
the target you wish to import:

```build
# //my/project/BUILD
cc_library(
    name = "somelib",
    srcs = ["somelib.c"],
    hdrs = ["somelib.h"],
    aspect_hints = ["@build_bazel_rules_swift//swift:auto_module"],
)
```

When this `cc_library` is a dependency of a Swift target, a module map will be
generated for it. In this case, the module's name would be `my_project_somelib`.

#### Using an explicit module name

If you need to provide an explicit name for the module (for example, if it is
part of a third-party library that expects to be imported with a specific name),
then you can declare your own `swift_interop_hint` target to define the name:

```build
# //my/project/BUILD
cc_library(
    name = "somelib",
    srcs = ["somelib.c"],
    hdrs = ["somelib.h"],
    aspect_hints = [":somelib_swift_interop"],
)

swift_interop_hint(
    name = "somelib_swift_interop",
    module_name = "CSomeLib",
)
```

When this `cc_library` is a dependency of a Swift target, a module map will be
generated for it with the module name `CSomeLib`.
""",
    implementation = _swift_interop_hint_impl,
)
