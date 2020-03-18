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

load(":swift_common.bzl", "swift_common")
load(":utils.bzl", "merge_runfiles")

def _swift_c_module_impl(ctx):
    module_map = ctx.file.module_map

    deps = ctx.attr.deps
    cc_infos = [dep[CcInfo] for dep in deps]
    data_runfiles = [dep[DefaultInfo].data_runfiles for dep in deps]
    default_runfiles = [dep[DefaultInfo].default_runfiles for dep in deps]

    if cc_infos:
        cc_info = cc_common.merge_cc_infos(cc_infos = cc_infos)
        compilation_context = cc_info.compilation_context
    else:
        cc_info = None
        compilation_context = cc_common.create_compilation_context()

    providers = [
        # We must repropagate the dependencies' DefaultInfos, otherwise we
        # will lose runtime dependencies that the library expects to be
        # there during a test (or a regular `bazel run`).
        DefaultInfo(
            data_runfiles = merge_runfiles(data_runfiles),
            default_runfiles = merge_runfiles(default_runfiles),
            files = depset([module_map]),
        ),
        swift_common.create_swift_info(
            modules = [
                swift_common.create_module(
                    name = ctx.attr.module_name,
                    clang = swift_common.create_clang_module(
                        compilation_context = compilation_context,
                        module_map = module_map,
                        # TODO(b/142867898): Precompile the module and place it
                        # here.
                        precompiled_module = None,
                    ),
                ),
            ],
        ),
    ]

    if cc_info:
        providers.append(cc_info)

    return providers

swift_c_module = rule(
    attrs = {
        "module_map": attr.label(
            allow_single_file = True,
            doc = """\
The module map file that should be loaded to import the C library dependency
into Swift.
""",
            mandatory = True,
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
        "deps": attr.label_list(
            allow_empty = False,
            doc = """\
A list of C targets (or anything propagating `CcInfo`) that are dependencies of
this target and whose headers may be referenced by the module map.
""",
            mandatory = True,
            providers = [[CcInfo]],
        ),
    },
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
)
