load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

# A dependency library built with `library_evolution`, so it emits a
# `.swiftinterface` in addition to a `.swiftmodule`. Consumers of this library
# can key their action cache on the swiftinterface when the
# `swift.use_swiftinterface_for_caching` feature is enabled.
swift_library(
    name = "upstream_lib",
    srcs = ["UpstreamLib.swift"],
    library_evolution = True,
    module_name = "UpstreamLib",
    tags = FIXTURE_TAGS,
)

# A dependency library built WITHOUT `library_evolution`, so it does not emit
# a `.swiftinterface`. Used to exercise the mixed-graph fallback: even with the
# `swift.use_swiftinterface_for_caching` feature enabled, this library's
# `.swiftmodule` still enters downstream compile actions' cache-key inputs
# to preserve correctness.
swift_library(
    name = "upstream_lib_no_evolution",
    srcs = ["UpstreamLibNoEvolution.swift"],
    library_evolution = False,
    module_name = "UpstreamLibNoEvolution",
    tags = FIXTURE_TAGS,
)

# Downstream client that depends only on the library-evolution dep. Its
# SwiftCompile action is the primary target of the tests: with the feature on,
# `UpstreamLib.swiftinterface` participates in the cache key while the
# `.swiftmodule` is provided via `unused_inputs_list`.
swift_library(
    name = "downstream_client",
    srcs = ["DownstreamClient.swift"],
    library_evolution = True,
    module_name = "DownstreamClient",
    tags = FIXTURE_TAGS,
    deps = [":upstream_lib"],
)

# Downstream client with a mixed dep set: one library-evolution dep and one
# non-library-evolution dep. Used to verify fallback behavior.
#
# Note: `library_evolution` is intentionally NOT set on this target. Swift
# refuses to let a library_evolution module import a non-library_evolution
# module (binary compatibility can't be guaranteed), so a mixed-dep client
# must not be library_evolution itself. This does not affect what the test
# verifies — the feature's fallback path is exercised by the shape of the
# transitive Swift deps, not by whether the current target has an interface.
swift_library(
    name = "downstream_client_mixed",
    srcs = ["DownstreamClientMixed.swift"],
    module_name = "DownstreamClientMixed",
    tags = FIXTURE_TAGS,
    deps = [
        ":upstream_lib",
        ":upstream_lib_no_evolution",
    ],
)
