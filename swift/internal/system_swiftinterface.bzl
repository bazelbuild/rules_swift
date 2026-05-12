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

"""Compile a system SDK swiftinterface to a consumable swiftmodule."""

load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo", "create_swift_module_context", "create_swift_module_inputs")
load("@build_bazel_rules_swift//swift:swift_common.bzl", "swift_common")
load("@build_bazel_rules_swift//swift/internal:compiling.bzl", "compile_module_interface")
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_SUPPRESS_WARNINGS",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_ADD_DEFAULT_PRECOMPILED_MODULES",
    "SWIFT_FEATURE_USE_C_MODULES",
    "SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP",
    "SWIFT_FEATURE_VFSOVERLAY",
)
load("@build_bazel_rules_swift//swift/internal:system_module_transition.bzl", "sdk_min_os_transition", "sdk_min_os_transition_attrs")
load("@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl", "SWIFT_SDK_TOOLCHAIN_TYPE")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _direct_clang_module_for_name(deps, module_name):
    for dep in deps:
        if SwiftInfo not in dep:
            continue
        for module in dep[SwiftInfo].direct_modules:
            if module.name == module_name and module.clang:
                return module.clang
    return None

def _system_swiftinterface_impl(ctx):
    swift_toolchain = swift_common.get_toolchain(ctx, toolchain_type = SWIFT_SDK_TOOLCHAIN_TYPE)
    deps = ctx.attr.modules
    swift_infos = [dep[SwiftInfo] for dep in deps if SwiftInfo in dep]
    cc_info = cc_common.merge_cc_infos(cc_infos = [
        dep[CcInfo]
        for dep in deps
        if CcInfo in dep
    ])

    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = ctx.features + [
            SWIFT_FEATURE_EMIT_C_MODULE,
            SWIFT_FEATURE_SUPPRESS_WARNINGS,  # System swiftinterface files have many warnings that we can't do anything about
            SWIFT_FEATURE_SYSTEM_MODULE,
            SWIFT_FEATURE_USE_C_MODULES,
            # The interface compile must always run with the explicit
            # module map and `-disable-implicit-swift-modules`. SDK Swift
            # interfaces strict-check that they're being compiled by the
            # same compiler that produced the SDK; the implicit-modules
            # path can drift on a swiftc/SDK version mismatch and fail
            # the check. The explicit-map path threads each Swift
            # dependency in deliberately, which is what the rest of the
            # interface validation expects.
            SWIFT_FEATURE_USE_EXPLICIT_SWIFT_MODULE_MAP,
        ],
        # The interface compile is internal explicit-modules infrastructure;
        # vfsoverlay is mutually exclusive with the explicit module map (see
        # `compile_module_interface`), and the consumer's choice of vfsoverlay
        # has no bearing on how this SDK module is built.
        #
        # `add_default_precompiled_modules` is force-disabled here so that
        # `-disable-implicit-swift-modules` does *not* fire for SDK
        # interface compiles. The scanner only declares the direct module
        # deps in `modules = [...]`; with implicit loading off, swiftc
        # rejects transitive references like `os` that are reachable from
        # the consumer's `system_modules` dep but not from the
        # `system_swiftinterface` rule's own deps.
        unsupported_features = [
            SWIFT_FEATURE_ADD_DEFAULT_PRECOMPILED_MODULES,
            SWIFT_FEATURE_VFSOVERLAY,
        ],
        swift_toolchain = swift_toolchain,
    )

    compile_result = compile_module_interface(
        actions = ctx.actions,
        clang_module = _direct_clang_module_for_name(deps, ctx.attr.module_name),
        compilation_contexts = [cc_info.compilation_context],
        feature_configuration = feature_configuration,
        is_framework = ctx.attr.is_framework,
        module_name = ctx.attr.module_name,
        swiftinterface_file = ctx.attr.system_swiftinterface,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = ctx.attr.name,
        toolchain_type = SWIFT_SDK_TOOLCHAIN_TYPE,
    )

    compiled_module = compile_result.module_context.swift.swiftmodule
    module_context = create_swift_module_context(
        name = ctx.attr.module_name,
        clang = compile_result.module_context.clang,
        is_framework = ctx.attr.is_framework,
        is_system = True,
        swift = create_swift_module_inputs(
            swiftdoc = None,
            swiftinterface = None,
            swiftmodule = compiled_module,
        ),
    )

    return [
        DefaultInfo(files = depset([compiled_module])),
        SwiftInfo(
            modules = [module_context],
            swift_infos = swift_infos,
        ),
        cc_info,
    ]

system_swiftinterface = rule(
    cfg = sdk_min_os_transition,
    attrs = sdk_min_os_transition_attrs() | {
        "is_framework": attr.bool(
            default = False,
            doc = "Whether the compiled Swift interface represents a framework module.",
        ),
        "module_name": attr.string(
            doc = "The name of the Swift module represented by this target.",
            mandatory = True,
        ),
        "modules": attr.label_list(
            allow_empty = True,
            doc = """\
A list of system modules that this Swift interface depends on. Named `modules`
instead of `deps` so the standard Swift `swift_clang_module_aspect` doesn't
recurse into the SDK module graph from consumers.
""",
            mandatory = False,
            providers = [[CcInfo, SwiftInfo]],
        ),
        "system_swiftinterface": attr.string(
            doc = """\
The path to a system Swift textual interface.

Variables `__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__` will be
substituted.
""",
            mandatory = True,
        ),
    },
    doc = """\
Compiles an Xcode-provided Swift textual interface into a `.swiftmodule` for a
system module that is not available in the toolchain's prebuilt module cache.
""",
    implementation = _system_swiftinterface_impl,
    toolchains = swift_common.use_toolchain(toolchain_type = SWIFT_SDK_TOOLCHAIN_TYPE),
    fragments = ["cpp"],
)
