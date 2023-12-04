# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""
Defines a rule that generates a Swift library from protocol buffer sources.
"""

load(
    "@bazel_skylib//lib:dicts.bzl", 
    "dicts",
)
load(
    "@rules_proto//proto:defs.bzl",
    "ProtoInfo",
)
load(
    "//proto:compiler.bzl", 
    "SwiftProtoCompilerInfo",
)
load(
    "//proto:util.bzl",
    "proto_path",
)
load(
    "//swift:swift.bzl",
    "swift_common",
    "swift_clang_module_aspect",
)

SwiftProtoImportInfo = provider(
    doc = """
    Information aggregated by the Swift proto library aspect.
    """,
    fields = {
        "imports": "Depset of proto source files from the ProtoInfo providers in the protos attributes of swift_proto_library dependencies."
    }
)

def _get_module_name(attr, target_label):
    """Gets the module name from the given attributes and target label.

    Uses the module name from the attribute if provided, 
    or failing this, falls back to the derived module name.
    """
    module_name = attr.module_name
    if not module_name:
        module_name = swift_common.derive_module_name(target_label)
    return module_name

def _get_imports(aspect_ctx, module_name):
    """Creates a depset of proto sources, ProtoInfo providers, and module names.

    The direct dependencies come from the protos attribute,
    and the transitive dependencies come from an aspect over the deps attribute,
    which extracts those same direct dependencies from the dependencies respective
    protos attributes.
    """

    # Extract the proto deps:
    proto_deps = getattr(aspect_ctx.attr, "protos", [])

    # Collect the direct proto source files from the proto deps:
    direct_imports = dict()
    for proto_dep in proto_deps:
        for proto_src in proto_dep[ProtoInfo].check_deps_sources.to_list():
            path = proto_path(proto_src, proto_dep[ProtoInfo])
            direct_imports["{}={}".format(path, module_name)] = True

    # Collect the transitive proto source files from the deps:
    deps = getattr(aspect_ctx.attr, "deps", [])
    transitive_imports = [
        dep[SwiftProtoImportInfo].imports
        for dep in deps
        if SwiftProtoImportInfo in dep
    ]

    # Create a depset of the direct + transitive proto imports:
    return depset(direct = direct_imports.keys(), transitive = transitive_imports)

def _swift_proto_library_aspect_impl(target, aspect_ctx):
    module_name = _get_module_name(aspect_ctx.rule.attr, target.label)
    imports = _get_imports(aspect_ctx, module_name)
    return [SwiftProtoImportInfo(imports = imports)]

_swift_proto_library_aspect = aspect(
    _swift_proto_library_aspect_impl,
    attr_aspects = [
        "deps",
    ],
    doc = """\
    Traverses the deps attributes of the swift_proto_library targets,
    and creates a depset from their respective protos attributes as well as their
    module names.
    """
)

def _swift_proto_library_impl(ctx):

    # Get the module name and gather the depset of imports and module names:
    module_name = _get_module_name(ctx.attr, ctx.label)
    imports = _get_imports(ctx, module_name)

    # Use the proto compiler to compile the swift sources for the proto deps:
    compilers = ctx.attr.compilers
    proto_deps = ctx.attr.protos
    swift_srcs = []
    for c in compilers:
        compiler = c[SwiftProtoCompilerInfo]
        swift_srcs.extend(compiler.compile(
            ctx,
            compiler = compiler,
            proto_infos = [d[ProtoInfo] for d in proto_deps],
            imports = imports,
        ))
    
    return [
        DefaultInfo(files = depset(swift_srcs))
    ]

new_swift_proto_library = rule(
    attrs = dicts.add(
        swift_common.library_rule_attrs(
            additional_deps_aspects = [
                _swift_proto_library_aspect,
                swift_clang_module_aspect,
            ],
            requires_srcs = False
        ),
        {
            "protos": attr.label_list(
                doc = """\
                Exactly one `proto_library` target (or any target that propagates a `proto`
                provider) from which the Swift library should be generated.
                """,
                providers = [ProtoInfo],
            ),
            "compilers": attr.label_list(
                providers = [SwiftProtoCompilerInfo],
                default = ["//proto:swift_proto"],
            ),
        },
    ),
    doc = """\
    Generates a Swift library from protocol buffer sources.

    ```python
    proto_library(
        name = "foo",
        srcs = ["foo.proto"],
    )

    swift_proto_library(
        name = "foo_swift",
        protos = [":foo"],
    )
    ```

    You should have one proto_library and one swift_proto_library per proto package.
    If your protos depend on protos from other packages, add a dependency between
    the swift_proto_library targets which mirrors the dependency between the proto targets.

    ```python
    proto_library(
        name = "bar",
        srcs = ["bar.proto"],
        deps = [":foo"],
    )

    swift_proto_library(
        name = "bar_swift",
        protos = [":bar"],
        deps = [":foo_swift"],
    )
    ```
    """,
    implementation = _swift_proto_library_impl,
)
