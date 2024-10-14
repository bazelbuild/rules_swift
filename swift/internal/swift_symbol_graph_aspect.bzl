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

"""Implementation of the `swift_symbol_graph_aspect` aspect.

The Swift build rules contain two subtly different symbol graph extraction
aspects; the public one (`swift_symbol_graph_extract`) meant for general usage,
and a private one used by `swift_test` for XCTest discovery. This file contains
the core implementation and a factory function used to create the concrete
aspects; the public aspect is exported by the `swift_symbol_graph_aspect.bzl`
file in the parent directory.
"""

load(
    "@build_bazel_rules_swift//swift:providers.bzl",
    "SwiftInfo",
    "SwiftSymbolGraphInfo",
)
load(
    "@build_bazel_rules_swift//swift:swift_clang_module_aspect.bzl",
    "swift_clang_module_aspect",
)
load(":features.bzl", "configure_features")
load(":symbol_graph_extracting.bzl", "extract_symbol_graph")
load(":toolchain_utils.bzl", "get_swift_toolchain", "use_swift_toolchain")

visibility([
    "@build_bazel_rules_swift//swift/...",
])

def _make_swift_symbol_graph_aspect_impl(
        output_distinguisher = None,
        wrapper_provider = None):
    """Creates the implementation function for a symbol graph aspect.

    Args:
        output_distinguisher: If set, a string that will be appended to the
            output directory name for each target. This allows multiple
            instances of the aspect to be used on the same target without their
            outputs colliding.
        wrapper_provider: If set, the provider to use to wrap the symbol graph
            provider. If not set, the symbol graph provider will be used
            directly. If set, the provider must have a single field named
            `symbol_graph_info` that will be set to the underlying symbol graph
            provider.
    Returns:
        The aspect implementation function.
    """

    def _wrap(provider):
        """Wraps the symbol graph provider if necessary."""
        if wrapper_provider:
            return wrapper_provider(symbol_graph_info = provider)
        return provider

    def _unwrap(target):
        """Unwraps the symbol graph provider if necessary."""
        if wrapper_provider:
            if wrapper_provider in target:
                return target[wrapper_provider].symbol_graph_info
            return None

        if SwiftSymbolGraphInfo in target:
            return target[SwiftSymbolGraphInfo]
        return None

    def _impl(target, aspect_ctx):
        """The actual aspect implementation function that will be returned."""
        symbol_graphs = []

        if SwiftInfo in target:
            swift_toolchain = get_swift_toolchain(aspect_ctx)
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

            # Only extract the symbol graphs of modules when the target compiles
            # Swift or Objective-C code.
            compiles_code = [
                action
                for action in target.actions
                if action.mnemonic in (
                    "SwiftCompile",
                    "SwiftCompileModule",
                    "SwiftPrecompileCModule",
                )
            ]
            if compiles_code:
                for module in swift_info.direct_modules:
                    if module.is_system:
                        continue

                    if output_distinguisher:
                        output_name = "{}.{}.symbolgraphs".format(
                            target.label.name,
                            output_distinguisher,
                        )
                    else:
                        output_name = "{}.symbolgraphs".format(
                            target.label.name,
                        )
                    output_dir = aspect_ctx.actions.declare_directory(
                        output_name,
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
            symbol_graph_info = _unwrap(dep)
            if symbol_graph_info:
                transitive_symbol_graphs.append(
                    symbol_graph_info.transitive_symbol_graphs,
                )

        return [
            _wrap(
                SwiftSymbolGraphInfo(
                    direct_symbol_graphs = symbol_graphs,
                    transitive_symbol_graphs = depset(
                        symbol_graphs,
                        transitive = transitive_symbol_graphs,
                    ),
                ),
            ),
        ]

    return _impl

SwiftTestDiscoverySymbolGraphInfo = provider(
    doc = "Wraps the symbol graph info for test discovery.",
    fields = {
        "symbol_graph_info": """\
The underlying `SwiftSymbolGraphInfo` provider for the target.
""",
    },
)

# Used only by `_testonly_symbol_graph_aspect_impl` below.
_test_discovery_swift_symbol_graph_aspect_impl = _make_swift_symbol_graph_aspect_impl(
    output_distinguisher = "test_discovery",
    wrapper_provider = SwiftTestDiscoverySymbolGraphInfo,
)

def _testonly_symbol_graph_aspect_impl(target, aspect_ctx):
    ignored = not getattr(aspect_ctx.rule.attr, "testonly", False)

    if ignored:
        # It's safe to return early (and not propagate transitive info) because
        # a non-`testonly` target can't depend on a `testonly` target, so there
        # is no possibility of losing anything we'd want to keep.
        return [
            SwiftTestDiscoverySymbolGraphInfo(
                symbol_graph_info = SwiftSymbolGraphInfo(
                    direct_symbol_graphs = [],
                    transitive_symbol_graphs = depset(),
                ),
            ),
        ]

    return _test_discovery_swift_symbol_graph_aspect_impl(target, aspect_ctx)

def make_swift_symbol_graph_aspect(
        *,
        default_minimum_access_level,
        doc = "",
        testonly_targets,
        output_distinguisher = None,
        wrapper_provider = None):
    """Creates an aspect that extracts Swift symbol graphs from dependencies.

    Args:
        default_minimum_access_level: The default minimum access level of the
            declarations that should be emitted in the symbol graphs. A rule
            that applies this aspect can let users override this value if it
            also provides an attribute named `minimum_access_level`.
        doc: The documentation string for the aspect.
        output_distinguisher: If set, a string that will be appended to the
            output directory name for each target. This allows multiple
            instances of the aspect to be used on the same target without their
            outputs colliding.
        testonly_targets: If True, symbol graphs will only be extracted from
            targets that have the `testonly` attribute set.
        wrapper_provider: If set, the provider to use to wrap the symbol graph
            provider. If not set, the symbol graph provider will be used
            directly. If set, the provider must have a single field named
            `symbol_graph_info` that will be set to the underlying symbol graph
            provider.

    Returns:
        An `aspect` that can be applied to a rule's dependencies.
    """
    if testonly_targets:
        aspect_impl = _testonly_symbol_graph_aspect_impl
        provides = [SwiftTestDiscoverySymbolGraphInfo]
    else:
        aspect_impl = _make_swift_symbol_graph_aspect_impl(
            output_distinguisher = output_distinguisher,
            wrapper_provider = wrapper_provider,
        )
        if wrapper_provider:
            provides = [wrapper_provider]
        else:
            provides = [SwiftSymbolGraphInfo]

    return aspect(
        attr_aspects = ["deps"],
        attrs = {
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
        doc = doc,
        fragments = ["cpp"],
        implementation = aspect_impl,
        provides = provides,
        requires = [swift_clang_module_aspect],
        toolchains = use_swift_toolchain(),
    )
