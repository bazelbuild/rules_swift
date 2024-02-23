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
Defines a rule that generates Swift libraries from protocol buffer sources.
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
    "//swift/internal:attrs.bzl",
    "swift_config_attrs",
)
load(
    "//swift/internal:providers.bzl",
    "SwiftInfo",
    "SwiftProtoCompilerInfo",
    "SwiftProtoInfo",
    "SwiftToolchainInfo",
)
load(
    "//swift/internal:swift_common.bzl",
    "swift_common",
)

# _swift_proto_library_group_aspect

def _swift_proto_library_group_aspect_impl(target, aspect_ctx):
    print("target: {}".format(target.label))
    print("rule: {}".format(aspect_ctx.rule))
    pass
    # module_name = _get_module_name(aspect_ctx.rule.attr, target.label)
    # imports = _get_imports(aspect_ctx.rule.attr, module_name)
    # return [SwiftProtoImportInfo(imports = imports)]

_swift_proto_library_group_aspect = aspect(
    _swift_proto_library_group_aspect_impl,
    attr_aspects = [
        "deps",
    ],
    attrs = dicts.add(
        swift_common.toolchain_attrs(),
        swift_config_attrs(),
    ),
    doc = """\
    Generates and compiles Swift sources from targets propagating `ProtoInfo` providers.
    """,
    fragments = ["cpp"],
)

# swift_proto_library_group

def _swift_proto_library_group_impl(ctx):
    pass

swift_proto_library_group = rule(
    attrs =  {
        "protos": attr.label_list(
            doc = """\
A list of `proto_library` targets (or targets producing `ProtoInfo`),
from which the Swift source files should be generated.
""",
            aspects = [_swift_proto_library_group_aspect],
            providers = [ProtoInfo],
        ),
        "compilers": attr.label_list(
            default = ["//proto/compilers:swift_proto"],
            doc = """\
One or more `swift_proto_compiler` target (or targets producing `SwiftProtoCompilerInfo`),
from which the Swift protos will be generated.
""",
            providers = [SwiftProtoCompilerInfo],
        ),
    },
    implementation = _swift_proto_library_group_impl,
)