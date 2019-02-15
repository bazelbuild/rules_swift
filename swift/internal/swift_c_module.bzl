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

load(":providers.bzl", "SwiftClangModuleInfo")

def _swift_c_module_impl(ctx):
    if len(ctx.attr.deps) > 1:
        fail("swift_c_module may have no more than one dependency.", attr = "deps")

    module_map = ctx.file.module_map

    if len(ctx.attr.deps) == 1:
        dep = ctx.attr.deps[0]
        cc_info = dep[CcInfo]
        compilation_context = cc_info.compilation_context
        return [
            # Repropagate the dependency's `CcInfo` provider so that Swift targets only have to
            # depend on the module target, not also on the original library target. We must also
            # repropagate the dependency, otherwise things we will lose runtime dependencies that
            # the library expects to be there during a test (or a regular `bazel run`).
            cc_info,
            DefaultInfo(
                data_runfiles = dep[DefaultInfo].data_runfiles,
                default_runfiles = dep[DefaultInfo].default_runfiles,
                files = depset(direct = [module_map]),
            ),
            SwiftClangModuleInfo(
                transitive_compile_flags = depset(
                    # TODO(b/124373197): Expanding these depsets isn't great, but it's temporary
                    # until we get rid of this provider completely.
                    direct = [
                        "-I{}".format(p)
                        for p in compilation_context.includes.to_list()
                    ] + [
                        "-iquote{}".format(p)
                        for p in compilation_context.quote_includes.to_list()
                    ] + [
                        "-isystem{}".format(p)
                        for p in compilation_context.system_includes.to_list()
                    ],
                ),
                transitive_defines = compilation_context.defines,
                transitive_headers = compilation_context.headers,
                transitive_modulemaps = depset(direct = [module_map]),
            ),
        ]
    else:
        return [
            DefaultInfo(files = depset(direct = [module_map])),
            SwiftClangModuleInfo(
                transitive_compile_flags = depset(),
                transitive_defines = depset(),
                transitive_headers = depset(),
                transitive_modulemaps = depset(direct = [module_map]),
            ),
        ]

swift_c_module = rule(
    attrs = {
        "module_map": attr.label(
            allow_single_file = True,
            doc = """
The module map file that should be loaded to import the C library dependency
into Swift.
""",
            mandatory = True,
        ),
        "deps": attr.label_list(
            allow_empty = False,
            doc = """
A list containing at most one `cc_library` target that is being wrapped with a
new module map.

If you need to create a `swift_c_module` to that pulls headers from multiple
`cc_library` targets into a single module, create a new `cc_library` target
that wraps them in its `deps` and has no other `srcs` or `hdrs`, and have the
module target depend on that.
""",
            mandatory = True,
            providers = [[CcInfo]],
        ),
    },
    doc = """
Wraps a `cc_library` in a new module map that allows it to be imported into
Swift to access its C interfaces.

NOTE: Swift at this time does not support interop directly with C++. Any headers
referenced by a module map that is imported into Swift must have only C features
visible, often by using preprocessor conditions like `#if __cplusplus` to hide
any C++ declarations.

The `cc_library` rule in Bazel does not produce module maps that are compatible
with Swift. In order to make interop between Swift and C possible, users can
write their own module map that includes any of the transitive public headers of
the `cc_library` dependency of this target and has a module name that is a valid
Swift identifier.

Then, write a `swift_{binary,library,test}` target that depends on this
`swift_c_module` target and the Swift sources will be able to import the module
with the name given in the module map.
""",
    implementation = _swift_c_module_impl,
)
