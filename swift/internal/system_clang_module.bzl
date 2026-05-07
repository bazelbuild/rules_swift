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

"""Implementation of the `system_clang_module` rule."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo", "create_clang_module_inputs", "create_swift_module_context")
load("@build_bazel_rules_swift//swift:swift_common.bzl", "swift_common")
load("@build_bazel_rules_swift//swift/internal:compiling.bzl", "precompile_clang_module")
load(
    "@build_bazel_rules_swift//swift/internal:feature_names.bzl",
    "SWIFT_FEATURE_EMIT_C_MODULE",
    "SWIFT_FEATURE_SYSTEM_MODULE",
    "SWIFT_FEATURE_USE_C_MODULES",
)
load("@build_bazel_rules_swift//swift/internal:system_module_transition.bzl", "sdk_min_os_transition", "sdk_min_os_transition_attrs")
load("@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl", "SWIFT_TOOLCHAIN_TYPE")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _system_clang_module_impl(ctx):
    swift_toolchain = swift_common.get_toolchain(ctx)
    module_map = ctx.attr.system_module_map
    deps = ctx.attr.modules

    if ctx.attr.module_name in ("XCTest", "XCUIAutomation", "StoreKitTest"):
        framework_dir = paths.dirname(paths.dirname(paths.dirname(module_map)))
        compilation_context_for_system_module = cc_common.create_compilation_context(framework_includes = depset([framework_dir]))
    else:
        compilation_context_for_system_module = cc_common.create_compilation_context()

    swift_infos = [dep[SwiftInfo] for dep in deps if SwiftInfo in dep]
    cc_info = cc_common.merge_cc_infos(cc_infos = [
        CcInfo(compilation_context = compilation_context_for_system_module),
    ] + [dep[CcInfo] for dep in deps])

    requested_features = ctx.features + [
        SWIFT_FEATURE_SYSTEM_MODULE,
        SWIFT_FEATURE_USE_C_MODULES,
        SWIFT_FEATURE_EMIT_C_MODULE,
    ]

    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
    )

    compile_result = precompile_clang_module(
        actions = ctx.actions,
        cc_compilation_context = cc_info.compilation_context,
        feature_configuration = feature_configuration,
        module_map_file = module_map,
        module_name = ctx.attr.module_name,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = ctx.attr.name,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
    )
    precompiled_module = (
        compile_result.clang_module.precompiled_module if compile_result else None
    )

    clang_module_context = create_clang_module_inputs(
        compilation_context = cc_info.compilation_context,
        module_map = module_map,
        precompiled_module = precompiled_module,
    )

    return [
        DefaultInfo(
            # NOTE: This should never be none but sometimes the SDK contains empty modules
            files = depset([precompiled_module] if precompiled_module else []),
        ),
        SwiftInfo(
            modules = [
                create_swift_module_context(
                    name = ctx.attr.module_name,
                    clang = clang_module_context,
                    is_system = True,
                ),
            ],
            swift_infos = swift_infos,
        ),
        cc_info,
    ]

system_clang_module = rule(
    cfg = sdk_min_os_transition,
    attrs = sdk_min_os_transition_attrs() | {
        "modules": attr.label_list(
            allow_empty = True,
            doc = """\
A list of C targets (or anything propagating `CcInfo`) that this module
depends on. Named `modules` instead of `deps` so the standard Swift
`swift_clang_module_aspect` (which traverses `deps`) doesn't recurse into
the SDK module graph from consumers.
""",
            mandatory = False,
            providers = [[CcInfo]],
        ),
        "module_name": attr.string(
            doc = """\
The name of the top-level module in the module map that this target represents.

A single `module.modulemap` file can contain multiple top-level modules, this
attribute is used to specify which one this target corresponds to.
""",
            mandatory = True,
        ),
        "system_module_map": attr.string(
            doc = """\
The path to a system framework module map.

`__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__` will be substitued
""",
            mandatory = True,
        ),
    },
    implementation = _system_clang_module_impl,
    toolchains = swift_common.use_toolchain(),
    fragments = ["cpp"],
)
