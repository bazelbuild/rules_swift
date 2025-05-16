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

"""Implementation of the `swift_overlay` rule."""

load(
    "@build_bazel_rules_swift//swift/internal:attrs.bzl",
    "swift_deps_attr",
    "swift_library_rule_attrs",
)
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_EMIT_SWIFTINTERFACE",
    "SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION",
)
load(
    "@build_bazel_rules_swift//swift/internal:providers.bzl",
    "SwiftCompilerPluginInfo",
    "SwiftOverlayCompileInfo",
)
load(
    "@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl",
    "use_all_toolchains",
)
load(
    "@build_bazel_rules_swift//swift/internal:utils.bzl",
    "get_providers",
)
load(":providers.bzl", "SwiftInfo", "SwiftOverlayInfo")
load(":swift_clang_module_aspect.bzl", "swift_clang_module_aspect")

visibility("public")

def _swift_overlay_impl(ctx):
    deps = ctx.attr.deps
    private_deps = ctx.attr.private_deps

    features = list(ctx.features)
    if ctx.attr.library_evolution:
        features.append(SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION)
        features.append(SWIFT_FEATURE_EMIT_SWIFTINTERFACE)

    return [SwiftOverlayCompileInfo(
        label = ctx.label,
        srcs = ctx.files.srcs,
        additional_inputs = ctx.files.swiftc_inputs,
        copts = ctx.attr.copts,
        defines = ctx.attr.defines,
        disabled_features = ctx.disabled_features,
        enabled_features = ctx.features,
        library_evolution = ctx.attr.library_evolution,
        linkopts = ctx.attr.linkopts,
        plugins = get_providers(ctx.attr.plugins, SwiftCompilerPluginInfo),
        private_deps = struct(
            cc_infos = get_providers(private_deps, CcInfo),
            swift_infos = get_providers(private_deps, SwiftInfo),
            swift_overlay_infos = get_providers(private_deps, SwiftOverlayInfo),
        ),
        alwayslink = ctx.attr.alwayslink,
        deps = struct(
            cc_infos = get_providers(deps, CcInfo),
            swift_infos = get_providers(deps, SwiftInfo),
            swift_overlay_infos = get_providers(deps, SwiftOverlayInfo),
        ),
    )]

def _swift_overlay_attrs():
    """Returns the attribute dictionary for the `swift_overlay` rule."""
    attrs = swift_library_rule_attrs(additional_deps_aspects = [
        swift_clang_module_aspect,
    ])

    # Replace the `srcs` attribute with one that only allows Swift files.
    attrs["srcs"] = attr.label_list(
        allow_empty = False,
        allow_files = ["swift"],
        doc = """\
A list of `.swift` source files that will be compiled into the overlay.

Unlike other `swift_*` rules, `swift_overlay` does not support C/Objective-C
source files. Those files belong in the underlying C/Objective-C library that
the overlay is associated with, or in a mixed-language `swift_library` if the
Swift and C/Objective-C code need to mutually reference each other.

Except in very rare circumstances, a Swift source file should only appear in a
single `swift_*` target. Adding the same source file to multiple `swift_*`
targets can lead to binary bloat and/or symbol collisions. If specific sources
need to be shared by multiple targets, consider factoring them out into their
own `swift_library` instead.
""",
        flags = ["DIRECT_COMPILE_TIME_INPUT"],
        mandatory = True,
    )
    attrs["private_deps"] = swift_deps_attr(
        aspects = [swift_clang_module_aspect],
        doc = """\
A list of targets that are implementation-only dependencies of the target being
built. Libraries/linker flags from these dependencies will be propagated to
dependent for linking, but artifacts/flags required for compilation (such as
.swiftmodule files, C headers, and search paths) will not be propagated.
""",
    )

    # `swift_overlay` must not provide its own module name because it will be
    # taken from the target to which it is applied as an aspect hint. Likewise,
    # it cannot generate a header because we assume that this is a pure Swift
    # overlay that does not export any APIs that would be of interest to
    # C/Objective-C clients, and it should not have any other headers either.
    attrs.pop("module_name")
    attrs.pop("generated_header_name")
    attrs.pop("generates_header")
    attrs.pop("hdrs")

    # TODO: b/65410357 - More work is needed to support runfiles.
    attrs.pop("data")

    return attrs

swift_overlay = rule(
    attrs = _swift_overlay_attrs(),
    doc = """\
A Swift overlay that sits on top of a C/Objective-C library, allowing an author
of a C/Objective-C library to create additional Swift-specific APIs that are
automatically available when a Swift target depends on their C/Objective-C
library.

The Swift overlay will only be compiled when other Swift targets depend on the
original library that uses the overlay; non-Swift clients depending on the
original library will not cause the Swift overlay code to be built or linked.
This is done to retain optimium build performance and binary size for non-Swift
clients. For this reason, `swift_overlay` is **not** a general purpose mechanism
for creating mixed-language modules; `swift_overlay` does not support generation
of an Objective-C header.

The `swift_overlay` rule does not perform any compilation of its own. Instead,
it must be placed in the `aspect_hints` attribute of another rule such as
`objc_library` or `cc_library`. For example,

```build
objc_library(
    name = "MyModule",
    srcs = ["MyModule.m"],
    hdrs = ["MyModule.h"],
    aspect_hints = [":MyModule_overlay"],
    deps = [...],
)

swift_overlay(
    name = "MyModule_overlay",
    srcs = ["MyModule.swift"],
    deps = [...],
)
```

When some other Swift target, such as a `swift_library`, depends on `MyModule`,
the Swift code in `MyModule_overlay` will be compiled into the same module.
Therefore, when that library imports `MyModule`, it will see the APIs from the
`objc_library` and the `swift_overlay` as a single combined module.

When writing a Swift overlay, the Swift code must do a re-exporting import of
its own module in order to access the C/Objective-C APIs; they are not available
automatically. Continuing the example above, any Swift sources that want to use
or extend the API from the C/Objective-C side of the module would need to write
the following:

```swift
@_exported import MyModule
```

The `swift_overlay` rule supports all the same attributes as `swift_library`,
except for the following:

*   `module_name` is not supported because the overlay inherits the same module
    name as the target it is attached to.
*   `generates_header` and `generated_header_name` are not supported because it
    is assumed that the overlay is pure Swift code that does not export any APIs
    that would be of interest to C/Objective-C clients.

Aside from its module name and its underlying C/Objective-C module dependency,
`swift_overlay` does not inherit anything else from its associated target. If
the `swift_overlay` imports any modules other than its C/Objective-C side, the
overlay target must explicitly depend on them as well. This means that an
overlay can have a different set of dependencies than the underlying module, if
desired.

There is a tight coupling between a Swift overlay and the C/Objective-C module
to which it is being applied, so a specific `swift_overlay` target should only
be referenced by the `aspect_hints` of a single `objc_library` or `cc_library`
target. Referencing a `swift_overlay` from multiple targets' `aspect_hints` is
almost always an anti-pattern.
""",
    exec_groups = {
        # The `plugins` attribute associates its `exec` transition with this
        # execution group. Even though the group is otherwise not used in this
        # rule, we must resolve the Swift toolchain in this execution group so
        # that the execution platform of the plugins will have the same
        # constraints as the execution platform as the other uses of the same
        # toolchain, ensuring that they don't get built for mismatched
        # platforms.
        "swift_plugins": exec_group(
            toolchains = use_all_toolchains(),
        ),
    },
    fragments = ["cpp"],
    implementation = _swift_overlay_impl,
)
