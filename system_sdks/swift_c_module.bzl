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

"""Implementation of the `swift_c_module` rule."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@build_bazel_rules_swift//swift:providers.bzl", "SwiftInfo", "create_clang_module_inputs", "create_swift_module_context")
load("@build_bazel_rules_swift//swift:swift_common.bzl", "swift_common")
load("@build_bazel_rules_swift//swift/internal:compiling.bzl", "precompile_clang_module")
load("@build_bazel_rules_swift//swift/internal:feature_names.bzl", "SWIFT_FEATURE_SYSTEM_MODULE")
load("@build_bazel_rules_swift//swift/internal:utils.bzl", "merge_runfiles")
load("@build_bazel_rules_swift//swift/internal:toolchain_utils.bzl", "SWIFT_TOOLCHAIN_TYPE")

def _swift_c_module_impl(ctx):
    if (
        (ctx.file.module_map and ctx.attr.system_module_map) or
        (not ctx.file.module_map and not ctx.attr.system_module_map)
    ):
        fail("Must specify one (and only one) of module_map and system_module_map.")
    swift_toolchain = swift_common.get_toolchain(ctx)
    module_map = ctx.file.module_map or ctx.attr.system_module_map
    is_system = True if ctx.attr.system_module_map else False

    deps = ctx.attr.deps

    if ctx.attr.module_name in ("XCTest", "XCUIAutomation", "StoreKitTest"):
        framework_dir = paths.dirname(paths.dirname(paths.dirname(module_map)))
        compilation_context_for_system_module = cc_common.create_compilation_context(framework_includes = depset([framework_dir]),)
    else:
        compilation_context_for_system_module = cc_common.create_compilation_context()

    cc_info_for_system_module = CcInfo(compilation_context = compilation_context_for_system_module)

    cc_infos = [cc_info_for_system_module] + [dep[CcInfo] for dep in deps]
    swift_infos = [dep[SwiftInfo] for dep in deps if SwiftInfo in dep]
    data_runfiles = [dep[DefaultInfo].data_runfiles for dep in deps]
    default_runfiles = [dep[DefaultInfo].default_runfiles for dep in deps]

    if cc_infos:
        cc_info = cc_common.merge_cc_infos(cc_infos = cc_infos)
        compilation_context = cc_info.compilation_context
    else:
        compilation_context = cc_common.create_compilation_context()
        cc_info = CcInfo(compilation_context = compilation_context)

    requested_features = ctx.features
    if is_system:
        requested_features.append(SWIFT_FEATURE_SYSTEM_MODULE)

    feature_configuration = swift_common.configure_features(
        ctx = ctx,
        requested_features = requested_features,
        swift_toolchain = swift_toolchain,
    )

    module_name = ctx.attr.module_name

    pcm_outputs = precompile_clang_module(
        actions = ctx.actions,
        cc_compilation_context = compilation_context,
        feature_configuration = feature_configuration,
        module_map_file = module_map,
        module_name = module_name,
        swift_infos = swift_infos,
        swift_toolchain = swift_toolchain,
        target_name = ctx.attr.name,
        toolchain_type = SWIFT_TOOLCHAIN_TYPE,
    )
    precompiled_module = getattr(pcm_outputs, "pcm_file", None)

    clang_module_context = create_clang_module_inputs(
        compilation_context = cc_info.compilation_context,
        module_map = module_map,
        precompiled_module = precompiled_module,
    )
    providers = [
        # We must repropagate the dependencies' DefaultInfos, otherwise we
        # will lose runtime dependencies that the library expects to be
        # there during a test (or a regular `bazel run`).
        DefaultInfo(
            data_runfiles = merge_runfiles(data_runfiles),
            default_runfiles = merge_runfiles(default_runfiles),
            files = depset([module_map]) if not is_system else None,
        ),
        SwiftInfo(
            modules = [
                create_swift_module_context(
                    name = module_name,
                    clang = clang_module_context,
                ),
            ],
            swift_infos = swift_infos,
        ),
        cc_info,
    ]

    return providers

swift_c_module = rule(
    attrs = dicts.add(
        {
            "deps": attr.label_list(
                allow_empty = True,
                doc = """\
A list of C targets (or anything propagating `CcInfo`) that are dependencies of
this target and whose headers may be referenced by the module map.
""",
                mandatory = False,
                providers = [[CcInfo]],
            ),
            "module_map": attr.label(
                allow_single_file = True,
                doc = """\
The module map file that should be loaded to import the C library dependency
into Swift. This is mutally exclusive with `system_module_map`.
""",
                mandatory = False,
            ),
            "module_name": attr.string(
                doc = """\
The name of the top-level module in the module map that this target represents.

A single `module.modulemap` file can define multiple top-level modules. When
building with implicit modules, the presence of that module map allows any of
the modules defined in it to be imported. When building explicit modules,
however, there is a one-to-one correspondence between top-level modules and
BUILD targets and the module name must be known without reading the module map
file, so it must be provided directly. Therefore, one may have multiple
`swift_c_module` targets that reference the same `module.modulemap` file but
with different module names and headers.
""",
                mandatory = True,
            ),
            "system_module_map": attr.string(
                doc = """\
The path to a system framework module map. This is mutually exclusive with `module_map`.

Variables `__BAZEL_XCODE_SDKROOT__` and `__BAZEL_XCODE_DEVELOPER_DIR__` will be substitued
appropriately for, i.e.
`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`
and
`/Applications/Xcode.app/Contents/Developer` respectively.
""",
                mandatory = False,
            ),
        },
    ),
    doc = """\
Wraps one or more C targets in a new module map that allows it to be imported
into Swift to access its C interfaces.

The `cc_library` rule in Bazel does not produce module maps that are compatible
with Swift. In order to make interop between Swift and C possible, users have
one of two options:

1.  **Use an auto-generated module map.** In this case, the `swift_c_module`
    rule is not needed. If a `cc_library` is a direct dependency of a
    `swift_{binary,library,test}` target, a module map will be automatically
    generated for it and the module's name will be derived from the Bazel target
    label (in the same fashion that module names for Swift targets are derived).
    The module name can be overridden by setting the `swift_module` tag on the
    `cc_library`; e.g., `tags = ["swift_module=MyModule"]`.

2.  **Use a custom module map.** For finer control over the headers that are
    exported by the module, use the `swift_c_module` rule to provide a custom
    module map that specifies the name of the module, its headers, and any other
    module information. The `cc_library` targets that contain the headers that
    you wish to expose to Swift should be listed in the `deps` of your
    `swift_c_module` (and by listing multiple targets, you can export multiple
    libraries under a single module if desired). Then, your
    `swift_{binary,library,test}` targets should depend on the `swift_c_module`
    target, not on the underlying `cc_library` target(s).

NOTE: Swift at this time does not support interop directly with C++. Any headers
referenced by a module map that is imported into Swift must have only C features
visible, often by using preprocessor conditions like `#if __cplusplus` to hide
any C++ declarations.
""",
    implementation = _swift_c_module_impl,
    toolchains = swift_common.use_toolchain(),
    fragments = ["cpp"],
)