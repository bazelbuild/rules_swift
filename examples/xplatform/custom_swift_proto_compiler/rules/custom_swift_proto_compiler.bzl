# Copyright 2024 The Bazel Authors. All rights reserved.
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
Defines a rule for compiling Swift source files from ProtoInfo providers.
"""

load(
    "@bazel_skylib//lib:paths.bzl",
    "paths",
)
load(
    "//proto:proto.bzl",
    "SwiftProtoCompilerInfo",
    "swift_proto_common",
)
load(
    "//swift:swift.bzl",
    "SwiftInfo",
)

def _custom_swift_proto_compile(ctx, swift_proto_compiler_info, additional_compiler_info, proto_infos, module_mappings):
    """Compiles Swift source files from `ProtoInfo` providers.

    Args:
        ctx: The context of the aspect or rule.
        swift_proto_compiler_info: The `SwiftProtoCompilerInfo` provider.
        additional_compiler_info: Information passed from the library target to the compiler.
        proto_infos: List of `ProtoInfo` providers to compile.
        module_mappings: The module_mappings field of the `SwiftProtoInfo` for the library target.

    Returns:
        A list of .swift files generated by the compiler.
    """

    # Declare the Swift files that will be generated:
    swift_srcs = []
    transitive_proto_srcs_list = []
    proto_paths = {}
    for proto_info in proto_infos:
        transitive_proto_srcs_list.append(proto_info.transitive_sources)

        # Iterate over the proto sources in the `ProtoInfo` to gather information
        # about their proto sources and declare the swift files that will be generated:
        for proto_src in proto_info.check_deps_sources.to_list():
            # Derive the proto path:
            path = swift_proto_common.proto_path(proto_src, proto_info)
            if path in proto_paths:
                if proto_paths[path] != proto_src:
                    fail("proto files {} and {} have the same import path, {}".format(
                        proto_src.path,
                        proto_paths[path].path,
                        path,
                    ))
                continue
            proto_paths[path] = proto_src

            # Declare the Swift source files that will be generated:
            base_swift_src_path = paths.replace_extension(path, ".swift")
            swift_src_path = paths.join(ctx.label.name, base_swift_src_path)
            swift_src = ctx.actions.declare_file(swift_src_path)
            swift_srcs.append(swift_src)
    transitive_proto_srcs = depset(direct = [], transitive = transitive_proto_srcs_list)

    # Prevent complaint about unused variables:
    if additional_compiler_info and module_mappings:
        swift_srcs.extend([])

    # Build the arguments for compiler:
    arguments = ctx.actions.args()
    arguments.use_param_file("--param=%s")

    # Finally, add the proto paths:
    # arguments.add_all(proto_paths.keys())
    arguments.add_all(swift_srcs)

    # Run the compiler action:
    ctx.actions.run(
        inputs = depset(
            direct = [],
            transitive = [transitive_proto_srcs],
        ),
        tools = [swift_proto_compiler_info.internal.tools],
        outputs = swift_srcs,
        mnemonic = "SwiftProtocGen",
        executable = swift_proto_compiler_info.internal.compiler,
        arguments = [arguments],
    )

    return swift_srcs

def _custom_swift_proto_compiler_impl(ctx):
    return [
        SwiftProtoCompilerInfo(
            compile = _custom_swift_proto_compile,
            compiler_deps = ctx.attr.deps,
            bundled_proto_paths = [],
            internal = struct(
                compiler = ctx.executable._compiler,
                tools = ctx.attr._compiler[DefaultInfo].files_to_run,
            ),
        ),
    ]

custom_swift_proto_compiler = rule(
    implementation = _custom_swift_proto_compiler_impl,
    attrs = {
        "deps": attr.label_list(
            default = [],
            doc = """\
            List of targets providing SwiftInfo and CcInfo.
            Added as implicit dependencies for any swift_proto_library using this
            compiler. Typically, these are Well Known Types and proto runtime libraries.
            """,
            providers = [SwiftInfo],
        ),
        "_compiler": attr.label(
            doc = """\
            A proto compiler executable binary.
            """,
            default = "//examples/xplatform/custom_swift_proto_compiler/rules:custom_proto_compiler",
            executable = True,
            cfg = "exec",
        ),
    },
)
