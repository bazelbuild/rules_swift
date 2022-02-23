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

"""Implementation of the `swift_symbol_graph_aspect` aspect."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(":attrs.bzl", "swift_toolchain_attrs")
load(":derived_files.bzl", "derived_files")
load(":features.bzl", "configure_features")
load(
    ":providers.bzl",
    "SwiftInfo",
    "SwiftSymbolGraphInfo",
    "SwiftToolchainInfo",
)
load(":symbol_graph_extracting.bzl", "extract_symbol_graph")

def _swift_symbol_graph_aspect_impl(target, aspect_ctx):
    symbol_graphs = []

    if SwiftInfo in target:
        swift_toolchain = aspect_ctx.attr._toolchain[SwiftToolchainInfo]
        feature_configuration = configure_features(
            ctx = aspect_ctx,
            swift_toolchain = swift_toolchain,
            requested_features = aspect_ctx.features,
            unsupported_features = aspect_ctx.disabled_features,
        )

        swift_info = target[SwiftInfo]
        if CcInfo in target:
            compilation_context = target[CcInfo].compilation_context
        else:
            compilation_context = cc_common.create_compilation_context()

        minimum_access_level = aspect_ctx.attr.minimum_access_level

        for module in swift_info.direct_modules:
            output_dir = derived_files.symbol_graph_directory(
                actions = aspect_ctx.actions,
                target_name = target.label.name,
            )
            extract_symbol_graph(
                actions = aspect_ctx.actions,
                compilation_contexts = [compilation_context],
                feature_configuration = feature_configuration,
                minimum_access_level = minimum_access_level,
                module_name = module.name,
                output_dir = output_dir,
                swift_infos = [swift_info],
                swift_toolchain = swift_toolchain,
            )
            symbol_graphs.append(
                struct(
                    module_name = module.name,
                    symbol_graph_dir = output_dir,
                ),
            )

    # TODO(b/204480390): We intentionally don't propagate symbol graphs from
    # private deps at this time, since the main use case for them is
    # documentation. Are there use cases where we should consider this?
    transitive_symbol_graphs = []
    for dep in getattr(aspect_ctx.rule.attr, "deps", []):
        if SwiftSymbolGraphInfo in dep:
            symbol_graph_info = dep[SwiftSymbolGraphInfo]
            transitive_symbol_graphs.append(
                symbol_graph_info.transitive_symbol_graphs,
            )

    return [
        SwiftSymbolGraphInfo(
            direct_symbol_graphs = symbol_graphs,
            transitive_symbol_graphs = depset(
                symbol_graphs,
                transitive = transitive_symbol_graphs,
            ),
        ),
    ]

def _testonly_symbol_graph_aspect_impl(target, aspect_ctx):
    if not getattr(aspect_ctx.rule.attr, "testonly", False):
        # It's safe to return early (and not propagate transitive info) because
        # a non-`testonly` target can't depend on a `testonly` target, so there
        # is no possibility of losing anything we'd want to keep.
        return [
            SwiftSymbolGraphInfo(
                direct_symbol_graphs = [],
                transitive_symbol_graphs = depset(),
            ),
        ]

    return _swift_symbol_graph_aspect_impl(target, aspect_ctx)

def _make_swift_symbol_graph_aspect(
        *,
        default_minimum_access_level,
        doc = "",
        testonly_targets):
    """Creates an aspect that extracts Swift symbol graphs from dependencies.

    Args:
        default_minimum_access_level: The default minimum access level of the
            declarations that should be emitted in the symbol graphs. A rule
            that applies this aspect can let users override this value if it
            also provides an attribute named `minimum_access_level`.
        doc: The documentation string for the aspect.
        testonly_targets: If True, symbol graphs will only be extracted from
            targets that have the `testonly` attribute set.

    Returns:
        An `aspect` that can be applied to a rule's dependencies.
    """
    if testonly_targets:
        aspect_impl = _testonly_symbol_graph_aspect_impl
    else:
        aspect_impl = _swift_symbol_graph_aspect_impl

    return aspect(
        attr_aspects = ["deps"],
        attrs = dicts.add(
            swift_toolchain_attrs(),
            {
                "minimum_access_level": attr.string(
                    default = default_minimum_access_level,
                    doc = """\
The minimum access level of the declarations that should be emitted in the
symbol graphs.

This value must be either `fileprivate`, `internal`, `private`, or `public`. The
default value is {default_value}.
""".format(
                        default_value = default_minimum_access_level,
                    ),
                    values = [
                        "fileprivate",
                        "internal",
                        "private",
                        "public",
                    ],
                ),
            },
        ),
        doc = doc,
        fragments = ["cpp"],
        implementation = aspect_impl,
        provides = [SwiftSymbolGraphInfo],
    )

# This aspect is exported as public API by `swift_common`.
swift_symbol_graph_aspect = _make_swift_symbol_graph_aspect(
    default_minimum_access_level = "public",
    doc = """\
Extracts symbol graphs from Swift modules in the build graph.

This aspect propagates a `SwiftSymbolGraphInfo` provider on any target to which
it is applied. This provider will contain the transitive module graph
information for the target's dependencies, and if the target propagates Swift
modules via its `SwiftInfo` provider, it will also extract and propagate their
symbol graphs by invoking the `swift-symbolgraph-extract` tool.

For an example of how to apply this to a custom rule, refer to the
implementation of `swift_extract_symbol_graph`.
    """,
    testonly_targets = False,
)

# This aspect is only meant to be used by `swift_test` and should not be
# exported by `swift_common`.
test_discovery_symbol_graph_aspect = _make_swift_symbol_graph_aspect(
    default_minimum_access_level = "internal",
    testonly_targets = True,
)
