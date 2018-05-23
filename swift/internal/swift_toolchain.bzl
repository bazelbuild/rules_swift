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

"""BUILD rules used to provide a Swift toolchain on Linux.

The rules defined in this file are not intended to be used outside of the Swift
toolchain package. If you are looking for rules to build Swift code using this
toolchain, see `swift.bzl`.
"""

load(
    ":providers.bzl",
    "SwiftInfo",
    "SwiftToolchainInfo",
    "swift_cc_toolchain_info",
)
load(
    "@bazel_skylib//:lib.bzl",
    "collections",
    "dicts",
    "paths",
    "selects",
)

def _swift_toolchain_impl(ctx):
  toolchain_root = ctx.attr.root
  cc_toolchain = ctx.attr._cc_toolchain[cc_common.CcToolchainInfo]

  platform_lib_dir = "{toolchain_root}/lib/swift/{os}".format(
      os=ctx.attr.os,
      toolchain_root=toolchain_root,
  )

  # TODO(allevato): Support statically linking the Swift runtime.
  linker_opts = [
      "-fuse-ld={}".format(ctx.fragments.cpp.ld_executable),
      "-L{}".format(platform_lib_dir),
      "-Wl,-rpath,{}".format(platform_lib_dir),
      "-lm",
      "-lstdc++",
  ]

  # TODO(allevato): Move some of the remaining hardcoded values, like object
  # format, autolink-extract, and Obj-C interop support, to attributes so that
  # we can remove the assumptions that are only valid on Linux.
  return [
      SwiftToolchainInfo(
          action_environment={},
          cc_toolchain_info=swift_cc_toolchain_info(
              all_files=ctx.files._cc_toolchain,
              provider=cc_toolchain,
          ),
          cpu=ctx.attr.arch,
          execution_requirements={},
          implicit_deps=[],
          linker_opts=linker_opts,
          object_format="elf",
          requires_autolink_extract=True,
          root_dir=toolchain_root,
          spawn_wrapper=None,
          stamp=ctx.attr.stamp,
          supports_objc_interop=False,
          swiftc_copts=[],
          system_name=ctx.attr.os,
      ),
  ]

swift_toolchain = rule(
    attrs={
        "arch": attr.string(
            doc="""
The name of the architecture that this toolchain targets.

This name should match the name used in the toolchain's directory layout for
architecture-specific content, such as "x86_64" in "lib/swift/linux/x86_64".
""",
            mandatory=True,
        ),
        "os": attr.string(
            doc="""
The name of the operating system that this toolchain targets.

This name should match the name used in the toolchain's directory layout for
platform-specific content, such as "linux" in "lib/swift/linux".
""",
            mandatory=True,
        ),
        "root": attr.string(
            mandatory=True,
        ),
        "stamp": attr.label(
            doc="""
A `cc`-providing target that should be linked into any binaries that are built
with stamping enabled.
""",
            providers=[["cc"]],
        ),
        "_cc_toolchain": attr.label(
            cfg="host",
            default=Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            doc="""
The C++ toolchain from which other tools needed by the Swift toolchain (such as
`clang` and `ar`) will be retrieved.
""",
        ),
    },
    doc="Represents a Swift compiler toolchain.",
    fragments=["cpp"],
    implementation=_swift_toolchain_impl,
)
