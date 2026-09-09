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

"""Tests for the `swift.use_swiftinterface_for_caching` feature."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load(
    "//test/rules:action_inputs_test.bzl",
    "make_action_inputs_test_rule",
)

# `action_inputs_test` variant with `swift.use_swiftinterface_for_caching`
# enabled (`enable_library_evolution` / `emit_swiftinterface` are enabled by
# default in this repo's toolchain, but we make them explicit here so the
# tests remain valid if toolchain defaults change).
# NOTE: Only the new feature is toggled via `config_settings`. Whether each
# fixture library emits a swiftinterface is decided per-target by the
# `library_evolution` attribute on `swift_library` (which enables
# `swift.emit_swiftinterface` / `swift.emit_private_swiftinterface`
# automatically). Putting `swift.emit_swiftinterface` here would enable it
# for *every* target under test — including `upstream_lib_no_evolution` —
# defeating the fallback test.
_use_swiftinterface_for_caching_inputs_test = make_action_inputs_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "swift.use_swiftinterface_for_caching",
        ],
    },
)

# Control variant with the feature explicitly disabled.
_baseline_inputs_test = make_action_inputs_test_rule(
    config_settings = {
        "//command_line_option:features": [
            "-swift.use_swiftinterface_for_caching",
        ],
    },
)

def swiftinterface_for_caching_test_suite(name, tags = []):
    """Test suite for the `swift.use_swiftinterface_for_caching` feature.

    The feature moves each dependency's `.swiftmodule` from a compile action's
    cache-key `inputs` onto an `unused_inputs_list`, so downstream compile
    actions can be cached against the more-stable `.swiftinterface` of an
    upstream `library_evolution` dependency. Both files remain in the action's
    sandbox — only the cache-key membership changes.

    Bazel's Starlark analysis-test API does not expose an action's
    `unused_inputs_list` for direct assertion. Instead we verify the observable
    consequences of the feature:

    1. The action still receives every dependency artifact it needs to compile
       (swiftinterface + swiftmodule remain in `inputs`), so builds do not
       regress when the feature is enabled.
    2. When a dependency is not built with `library_evolution` (and therefore
       has no `.swiftinterface`), that dependency's `.swiftmodule` is not
       demoted — it stays in `inputs` so correctness is preserved in mixed
       graphs.
    3. A `build_test` sanity check: with the feature on, the fixture builds
       end-to-end.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # NOTE: A `swift_library` with `library_evolution = True` enables both
    # `swift.emit_swiftinterface` and `swift.emit_private_swiftinterface`, so
    # the dependency produces `UpstreamLib.swiftinterface` AND
    # `UpstreamLib.private.swiftinterface`. `transitive_swift_dependency_inputs`
    # prefers `private_swiftinterface` when both are available, so it is the
    # `.private.swiftinterface` file that ends up in downstream action inputs.

    # 1. With the feature enabled, the downstream compile action still lists
    #    the upstream's swiftinterface AND swiftmodule among its inputs. The
    #    swiftmodule appearance in `inputs` is expected — with
    #    `unused_inputs_list`, files are still declared as action inputs (so
    #    they land in the sandbox); Bazel simply excludes them from the action
    #    cache key. See `swift/internal/actions.bzl`.
    _use_swiftinterface_for_caching_inputs_test(
        name = "{}_downstream_sees_upstream_swiftinterface_when_feature_on".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        expected_inputs = [
            "UpstreamLib.private.swiftinterface",
            "UpstreamLib.swiftmodule",
        ],
        target_under_test = "//test/fixtures/swiftinterface_for_caching:downstream_client",
    )

    # 2. Fallback in mixed graphs: `upstream_lib_no_evolution` has no
    #    swiftinterface, so its swiftmodule must remain in the cache-key
    #    inputs (via `transitive_swift_dependency_inputs`'s fallback branch).
    #    The library-evolution dep's swiftinterface still shows up in inputs.
    _use_swiftinterface_for_caching_inputs_test(
        name = "{}_no_evolution_dep_falls_back_to_swiftmodule".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        expected_inputs = [
            "UpstreamLib.private.swiftinterface",
            "UpstreamLibNoEvolution.swiftmodule",
        ],
        target_under_test = "//test/fixtures/swiftinterface_for_caching:downstream_client_mixed",
    )

    # 3. Baseline (feature off): the swiftmodule is still an input, and so is
    #    the swiftinterface (the compiler receives the same file set in both
    #    modes). This contrast documents that our tests do not accidentally
    #    depend on feature-on vs feature-off *input* set changes — the
    #    difference is only in cache-key membership.
    _baseline_inputs_test(
        name = "{}_baseline_feature_off_inputs".format(name),
        tags = all_tags,
        mnemonic = "SwiftCompile",
        expected_inputs = [
            "UpstreamLib.private.swiftinterface",
            "UpstreamLib.swiftmodule",
        ],
        target_under_test = "//test/fixtures/swiftinterface_for_caching:downstream_client",
    )

    # 4. Smoke test: the fixture builds end-to-end with the feature enabled.
    build_test(
        name = "{}_build_smoke".format(name),
        targets = [
            "//test/fixtures/swiftinterface_for_caching:downstream_client",
            "//test/fixtures/swiftinterface_for_caching:downstream_client_mixed",
        ],
        tags = all_tags,
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
