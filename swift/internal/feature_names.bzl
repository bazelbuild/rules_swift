# Copyright 2020 The Bazel Authors. All rights reserved.
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

"""Constants defining feature names used throughout the build rules."""

# We use the following constants within the rule definitions to prevent the
# possibility of typos when referring to them as part of the implementation, but
# we explicitly do not export them since it's not a common practice to use them
# that way in BUILD files; the expectation is that the actual string literals
# would be used there. (There is also no good way to generate documentation yet
# for constants since they don't have "doc" attributes, so exposing them in a
# more structured way doesn't provide a benefit there either.)

# These features correspond to the current Bazel compilation mode. Exactly one
# of them will be enabled by the toolchain. (We define our own because we cannot
# depend on the equivalent C++ features being enabled if the toolchain does not
# require them for any of its behavior.)
SWIFT_FEATURE_DBG = "swift.dbg"
SWIFT_FEATURE_FASTBUILD = "swift.fastbuild"
SWIFT_FEATURE_OPT = "swift.opt"

# These features correspond to the current Bitcode mode as specified by the
# `apple` configuration fragment when targeting Apple platforms. At most one of
# these will be enabled by the toolchain.
SWIFT_FEATURE_BITCODE_EMBEDDED = "swift.bitcode_embedded"
SWIFT_FEATURE_BITCODE_EMBEDDED_MARKERS = "swift.bitcode_embedded_markers"

# This feature is enabled if coverage collection is enabled for the build. (See
# the note above about not depending on the C++ features.)
SWIFT_FEATURE_COVERAGE = "swift.coverage"

# If enabled, the `swift_test` rule will output an `.xctest` bundle for Darwin
# targets instead of a standalone binary. This is necessary for XCTest-based
# tests that use runtime reflection to locate test methods. This feature can be
# explicitly disabled on a per-target or per-package basis if needed to make
# `swift_test` output just a binary.
SWIFT_FEATURE_BUNDLED_XCTESTS = "swift.bundled_xctests"

# If enabled, the Swift compiler will emit a directory containing JSON files
# with timing information about the driver/frontend's actions. This directory
# will be emitted as a default output when a Swift target is built directly, and
# it will also be propagated in an output group named
# `swift_compile_stats_direct`. Typically this output group will not be accessed
# directly, but used by the `collect_swift_compile_stats` aspect to gather the
# transitive stats for the entire build.
SWIFT_FEATURE_COMPILE_STATS = "swift.compile_stats"

# If enabled, debug builds will use the `-debug-prefix-map` feature to remap the
# current working directory to `.`, which permits debugging remote or sandboxed
# builds.
SWIFT_FEATURE_DEBUG_PREFIX_MAP = "swift.debug_prefix_map"

# If enabled, coverage builds will use the `-coverage-prefix-map` feature to
# remap the current working directory to `.`, which increases reproducibility
# of remote builds.
SWIFT_FEATURE_COVERAGE_PREFIX_MAP = "swift.coverage_prefix_map"

# If enabled, C and Objective-C libraries that are direct or transitive
# dependencies of a Swift library will emit explicit precompiled modules that
# are compatible with Swift's ClangImporter and propagate them up the build
# graph.
SWIFT_FEATURE_EMIT_C_MODULE = "swift.emit_c_module"

# If enabled, when compiling an explicit C or Objectve-C module, every header
# included by the module being compiled must belong to one of the modules listed
# in its dependencies. This is ignored for system modules.
SWIFT_FEATURE_STRICT_MODULES = "swift.strict_modules"

# If enabled, the C or Objective-C target should be compiled as a system module.
SWIFT_FEATURE_SYSTEM_MODULE = "swift.system_module"

# If enabled, Swift compilation actions will use batch mode by passing
# `-enable-batch-mode` to `swiftc`. This is a new compilation mode as of
# Swift 4.2 that is intended to speed up non-incremental non-WMO builds by
# invoking a smaller number of frontend processes and passing them batches of
# source files.
SWIFT_FEATURE_ENABLE_BATCH_MODE = "swift.enable_batch_mode"

# If enabled, Swift compilation actions will pass the `-enable-testing` flag
# that modifies visibility controls to let a module be imported with the
# `@testable` attribute. This feature will be enabled by default for
# dbg/fastbuild builds and disabled by default for opt builds.
SWIFT_FEATURE_ENABLE_TESTING = "swift.enable_testing"

# If enabled, full debug info should be generated instead of line-tables-only.
# This is required when dSYMs are requested via the `--apple_generate_dsym` flag
# but the compilation mode is `fastbuild`, because `dsymutil` emits spurious
# warnings otherwise.
SWIFT_FEATURE_FULL_DEBUG_INFO = "swift.full_debug_info"

# If enabled, ClangImporter will perform implicit search for module maps and
# compile modules in the implicit module cache for any that were not provided
# explicitly on the command line. Otherwise, all modules must be provided
# explicitly.
SWIFT_FEATURE_IMPLICIT_MODULES = "swift.implicit_modules"

# If enabled, the compilation action for a target will produce an index store.
SWIFT_FEATURE_INDEX_WHILE_BUILDING = "swift.index_while_building"

# If enabled, Swift libraries, binaries, and tests will only have automatic
# dependencies on the targets provided by the toolchain's
# `required_implicit_deps` field but not those in the `optional_implicit_deps`
# field. Users may still explicitly list the latter in the `deps` of their
# targets if they are needed.
SWIFT_FEATURE_MINIMAL_DEPS = "swift.minimal_deps"

# If enabled, compilation actions and module map generation will assume that the
# header paths in module maps are relative to the current working directory
# (i.e., the workspace root); if disabled, header paths in module maps are
# relative to the location of the module map file.
SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD = "swift.module_map_home_is_cwd"

# If enabled, private headers (headers specified in the `srcs` of a target) will
# not be included in generated module maps.
# TODO(b/142867898): This only exists for compatibility with the existing
# Objective-C behavior in Bazel and should be removed.
SWIFT_FEATURE_MODULE_MAP_NO_PRIVATE_HEADERS = (
    "swift.module_map_no_private_headers"
)

# If enabled, the compilation action for a library target will not generate an
# Objective-C header for the module. This feature also implies
# `swift.no_generated_module_map`.
SWIFT_FEATURE_NO_GENERATED_HEADER = "swift.no_generated_header"

# If enabled, the compilation action for a library target will not generate a
# module map for the Objective-C generated header. Note that this feature
# is ignored if `swift.no_generated_header` is present.
SWIFT_FEATURE_NO_GENERATED_MODULE_MAP = "swift.no_generated_module_map"

# If enabled, builds using the "opt" compilation mode will invoke `swiftc` with
# the `-whole-module-optimization` flag (in addition to `-O`).
SWIFT_FEATURE_OPT_USES_WMO = "swift.opt_uses_wmo"

# If enabled, builds using the "opt" compilation mode will invoke `swiftc` with
# the `-Osize` flag instead of `-O`.
SWIFT_FEATURE_OPT_USES_OSIZE = "swift.opt_uses_osize"

# If enabled, Swift compiler invocations will use precompiled modules from
# dependencies instead of module maps and headers, if those dependencies provide
# them.
SWIFT_FEATURE_USE_C_MODULES = "swift.use_c_modules"

# If enabled, Swift compilation actions will use the same global Clang module
# cache used by Objective-C compilation actions. This is disabled by default
# because under some circumstances Clang module cache corruption can cause the
# Swift compiler to crash (sometimes when switching configurations or syncing a
# repository), but disabling it also causes a noticeable build time regression
# so it can be explicitly re-enabled by users who are not affected by those
# crashes.
SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE = "swift.use_global_module_cache"

# If enabled, actions invoking the Swift driver or frontend may write argument
# lists into response files (i.e., "@args.txt") to avoid passing command lines
# that exceed the system limit. Toolchains typically set this automatically if
# using a sufficiently recent version of Swift (4.2 or higher).
SWIFT_FEATURE_USE_RESPONSE_FILES = "swift.use_response_files"

# If enabled, Swift compilation actions will create a virtual file system
# overlay containing all its dependencies' `.swiftmodule` files and use that
# overlay as its sole search path. This improves build performance by avoiding
# worst-case O(N^2) search (N modules, each in its own subdirectory), especially
# when access to those paths involves traversing a networked file system.
SWIFT_FEATURE_VFSOVERLAY = "swift.vfsoverlay"

# If enabled, builds using the "dbg" compilation mode will explicitly disable
# swiftc from producing swiftmodules containing embedded file paths, which are
# inherently non-portable across machines.
#
# To used these modules from lldb, target settings must be correctly populated.
# For example:
#     target.swift-module-search-paths
#     target.swift-framework-search-paths
#     target.swift-extra-clang-flags
SWIFT_FEATURE_CACHEABLE_SWIFTMODULES = "swift.cacheable_swiftmodules"

# If enabled, enables features that require the library evolution compilation
# mode. If disabled, features that require library evolution mode are noops.
SWIFT_FEATURE_SUPPORTS_LIBRARY_EVOLUTION = "swift.supports_library_evolution"

# If enabled, requests the `-enable-library-evolution` swiftc flag which is
# required for newer features like swiftinterface file generation. If the
# `SWIFT_FEATURES_SUPPORTS_LIBRARY_EVOLUTION` feature is not enabled, this
# feature is a noop.
SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION = "swift.enable_library_evolution"

# If enabled, requests the swiftinterface file to be built on the swiftc
# invocation. If the `SWIFT_FEATURES_SUPPORTS_LIBRARY_EVOLUTION` feature is not
# enabled, this feature is a noop.
SWIFT_FEATURE_EMIT_SWIFTINTERFACE = "swift.emit_swiftinterface"

# If enabled, the toolchain supports private deps (implementation-only imports).
# This allows Bazel to avoid propagating swiftmodules of such dependencies
# higher in the dependency graph than they need to be.
SWIFT_FEATURE_SUPPORTS_PRIVATE_DEPS = "swift.supports_private_deps"

# If enabled, the .swiftmodule file for the affected target will not be
# embedded in debug info and propagated to the linker.
#
# The name of this feature is negative because it is meant to be a temporary
# workaround until ld64 is fixed (in Xcode 12) so that builds that pass large
# numbers of `-Wl,-add_ast_path,<path>` flags to the linker do not overrun the
# system command line limit.
SWIFT_FEATURE_NO_EMBED_DEBUG_MODULE = "swift.no_embed_debug_module"

# If enabled, the toolchain will directly generate from the raw proto files
# and not from the DescriptorSets.
#
# The DescriptorSets ProtoInfo exposes don't have source info, so comments in
# the .proto files don't get carried over to the generated Swift sources as
# documentation comments. https://github.com/bazelbuild/bazel/issues/9337
# is open to attempt to get that, but this provides a way to opt into forcing
# it.
#
# This does come with a minor risk for cross repository and/or generated proto
# files where the protoc command line might not be crafted correctly, so it
# remains opt in.
SWIFT_FEATURE_GENERATE_FROM_RAW_PROTO_FILES = "swift.generate_from_raw_proto_files"
