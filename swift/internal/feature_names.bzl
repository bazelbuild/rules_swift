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

visibility([
    "@build_bazel_rules_swift//swift/...",
])

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

# If True, transitive C headers will be always be passed as inputs to Swift
# compilation actions, even when building with explicit modules.
SWIFT_FEATURE_HEADERS_ALWAYS_ACTION_INPUTS = "swift.headers_always_action_inputs"

# This feature is enabled if coverage collection is enabled for the build. (See
# the note above about not depending on the C++ features.)
SWIFT_FEATURE_COVERAGE = "swift.coverage"

# If enabled, builds will use the `-file-prefix-map` feature to remap the
# current working directory to `.`, which permits debugging remote or sandboxed
# builds as well as hermetic index and coverage information. This requires
# Xcode 14 or newer.
SWIFT_FEATURE_FILE_PREFIX_MAP = "swift.file_prefix_map"

# If enabled, debug builds will use the `-debug-prefix-map` feature to remap the
# current working directory to `.`, which permits debugging remote or sandboxed
# builds.
SWIFT_FEATURE_DEBUG_PREFIX_MAP = "swift.debug_prefix_map"

# If enabled, C and Objective-C libraries that are direct or transitive
# dependencies of a Swift library will emit explicit precompiled modules that
# are compatible with Swift's ClangImporter and propagate them up the build
# graph.
SWIFT_FEATURE_EMIT_C_MODULE = "swift.emit_c_module"

# If enabled alongside `swift.index_while_building`, the indexstore will also
# contain records for symbols in system modules imported by the code being
# indexed.
SWIFT_FEATURE_INDEX_SYSTEM_MODULES = "swift.index_system_modules"

# If enabled, the compilation action for a target will also produce an index
# store among its outputs.
SWIFT_FEATURE_INDEX_WHILE_BUILDING = "swift.index_while_building"

# If enabled, indexing will be completely modular - PCMs and Swift Modules will only
# be indexed when they are compiled. While indexing a module/PCM, none of its dependencies
# will be indexed.
#
# NOTE: This is only applicable if both `SWIFT_FEATURE_EMIT_C_MODULE` and
# `SWIFT_FEATURE_INDEX_WHILE_BUILDING` are enabled as well. In addition, this feature requires
# Xcode 14 in order to work.
SWIFT_FEATURE_MODULAR_INDEXING = "swift.modular_indexing"

# If enabled, when compiling an explicit C or Objectve-C module, every header
# included by the module being compiled must belong to one of the modules listed
# in its dependencies. This is ignored for system modules.
SWIFT_FEATURE_LAYERING_CHECK = "swift.layering_check"

# If enabled, an error will be emitted when compiling Swift code if it imports
# any module that is not listed among the direct dependencies of the target.
# TOOD(b/73945280): Combine this into `swift.layering_check` once everything is
# layering-check clean.
SWIFT_FEATURE_LAYERING_CHECK_SWIFT = "swift.layering_check_swift"

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

# If enabled, compilation actions and module map generation will assume that the
# header paths in module maps are relative to the current working directory
# (i.e., the workspace root); if disabled, header paths in module maps are
# relative to the location of the module map file.
SWIFT_FEATURE_MODULE_MAP_HOME_IS_CWD = "swift.module_map_home_is_cwd"

# When code is compiled with ASAN enabled, a reference to a versioned symbol is
# emitted that ensures that the object files are linked to a version of the ASAN
# runtime library that is known to be compatible. If this feature is enabled,
# the versioned symbol reference will be omitted, allowing the object files to
# link to any version of the ASAN runtime library.
SWIFT_FEATURE_NO_ASAN_VERSION_CHECK = "swift.no_asan_version_check"

# If enabled, the compilation action for a library target will not generate a
# module map for the Objective-C generated header. This feature is ignored if
# the target is not generating a header.
SWIFT_FEATURE_NO_GENERATED_MODULE_MAP = "swift.no_generated_module_map"

# If enabled, builds using the "opt" compilation mode will invoke `swiftc` with
# the `-whole-module-optimization` flag (in addition to `-O`).
SWIFT_FEATURE_OPT_USES_WMO = "swift.opt_uses_wmo"

# If enabled, builds using the "opt" compilation mode will invoke `swiftc` with
# the `-Osize` flag instead of `-O`.
SWIFT_FEATURE_OPT_USES_OSIZE = "swift.opt_uses_osize"

# If enabled, and if the toolchain specifies a generated header rewriting tool,
# that tool will be invoked after compilation to rewrite the generated header in
# place.
SWIFT_FEATURE_REWRITE_GENERATED_HEADER = "swift.rewrite_generated_header"

# If enabled, Swift compiler invocations will use precompiled modules from
# dependencies instead of module maps and headers, if those dependencies provide
# them.
SWIFT_FEATURE_USE_C_MODULES = "swift.use_c_modules"

# If enabled, Swift modules for dependencies will be passed to the compiler
# using a JSON file instead of `-I` search paths.
SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP = "swift.use_explicit_swift_module_map"

# If enabled, Swift compilation actions will use the same global Clang module
# cache used by Objective-C compilation actions. This is disabled by default
# because under some circumstances Clang module cache corruption can cause the
# Swift compiler to crash (sometimes when switching configurations or syncing a
# repository), but disabling it also causes a noticeable build time regression
# so it can be explicitly re-enabled by users who are not affected by those
# crashes.
SWIFT_FEATURE_USE_GLOBAL_MODULE_CACHE = "swift.use_global_module_cache"

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

# If enabled, requests the `-enable-library-evolution` swiftc flag which is
# required for newer features like swiftinterface file generation.
SWIFT_FEATURE_ENABLE_LIBRARY_EVOLUTION = "swift.enable_library_evolution"

# If enabled, requests the swiftinterface file to be built on the swiftc
# invocation.
SWIFT_FEATURE_EMIT_SWIFTINTERFACE = "swift.emit_swiftinterface"

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

# A private feature that is set by the toolchain if a flag enabling WMO was
# passed on the command line using `--swiftcopt`. Users should never manually
# enable, disable, or query this feature.
SWIFT_FEATURE__WMO_IN_SWIFTCOPTS = "swift._wmo_in_swiftcopts"

# A private feature that is set by the toolchain if the flags `-num-threads 1`
# were passed on the command line using `--swiftcopt`. Users should never
# manually enable, disable, or query this feature.
SWIFT_FEATURE__NUM_THREADS_1_IN_SWIFTCOPTS = "swift._num_threads_1_in_swiftcopts"

# If enabled, requests the `-enforce-exclusivity=checked` swiftc flag which
# enables runtime checking of exclusive memory access on mutation.
SWIFT_FEATURE_CHECKED_EXCLUSIVITY = "swift.checked_exclusivity"

# If enabled, requests the `-enable-bare-slash-regex` swiftc flag which is
# required for forward slash regex expression literals.
SWIFT_FEATURE_ENABLE_BARE_SLASH_REGEX = "swift.enable_bare_slash_regex"

# If enabled, requests the `-disable-clang-spi` swiftc flag. Disables importing
# Clang SPIs as Swift SPIs.
SWIFT_FEATURE_DISABLE_CLANG_SPI = "swift.disable_clang_spi"

# If enabled, allow public symbols to be internalized at link time to support
# better dead-code stripping. This assumes that all clients of public types are
# part of the same link unit or that public symbols linked into frameworks are
# explicitly exported via `-exported_symbols_list`.
SWIFT_FEATURE_INTERNALIZE_AT_LINK = "swift.internalize_at_link"

# A private feature that is set by the toolchain if it supports macros (Swift
# 5.9 and above). Users should never manually enable, disable, or query this
# feature.
SWIFT_FEATURE__SUPPORTS_MACROS = "swift._supports_macros"
