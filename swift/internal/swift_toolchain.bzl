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

load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo")
load(
    "@bazel_skylib//:lib.bzl",
    "collections",
    "dicts",
    "partial",
    "paths",
    "selects",
)

def _default_linker_opts(
    cpp_fragment,
    os,
    toolchain_root,
    is_static,
    is_test):
  """Returns options that should be passed by default to `clang` when linking.

  This function is wrapped in a `partial` that will be propagated as part of the
  toolchain provider. The first three arguments are pre-bound; the `is_static`
  and `is_test` arguments are expected to be passed by the caller.

  Args:
    cpp_fragment: The `cpp` configuration fragment from which the `ld`
        executable is determined.
    os: The operating system name, which is used as part of the library path.
    toolchain_root: The toolchain's root directory.
    is_static: `True` to link against the static version of the Swift runtime,
        or `False` to link against dynamic/shared libraries.
    is_test: `True` if the target being linked is a test target.

  Returns:
    The command line options to pass to `clang` to link against the desired
    variant of the Swift runtime libraries.
  """
  # TODO(#8): Support statically linking the Swift runtime. Until then, the
  # partial's arguments are ignored to avoid Skylark lint errors.
  _ignore = (is_static, is_test)
  platform_lib_dir = "{toolchain_root}/lib/swift/{os}".format(
      os=os,
      toolchain_root=toolchain_root,
  )

  return [
      "-fuse-ld={}".format(cpp_fragment.ld_executable),
      "-L{}".format(platform_lib_dir),
      "-Wl,-rpath,{}".format(platform_lib_dir),
      "-lm",
      "-lstdc++",
  ]

def _modified_action_args(action_args, toolchain_tools):
  """Updates an argument dictionary with values from a toolchain.

  Args:
    action_args: The `kwargs` dictionary from a call to `actions.run` or
        `actions.run_shell`.
    toolchain_tools: A `depset` containing toolchain files that must be
        available to the action when it executes (executables and libraries).

  Returns:
    A dictionary that can be passed as the `**kwargs` to a call to one of the
    action running functions that has been modified to include the toolchain
    values.
  """
  modified_args = dict(action_args)

  # Add the toolchain's tools to the `tools` argument of the action.
  user_tools = modified_args.pop("tools", None)
  if type(user_tools) == type([]):
    tools = depset(direct=user_tools, transitive=[toolchain_tools])
  elif type(user_tools) == type(depset()):
    tools = depset(transitive=[user_tools, toolchain_tools])
  elif user_tools:
    fail("'tools' argument must be a sequence or depset.")
  else:
    tools = toolchain_tools
  modified_args["tools"] = tools

  return modified_args

def _run_action(toolchain_tools, actions, **kwargs):
  """Runs an action with the toolchain requirements.

  This is the implementation of the `action_registrars.run` partial, where the
  first argument is pre-bound to a toolchain-specific value.

  Args:
    toolchain_tools: A `depset` containing toolchain files that must be
        available to the action when it executes (executables and libraries).
    actions: The `Actions` object with which to register actions.
    **kwargs: Additional arguments that are passed to `actions.run`.
  """
  modified_args = _modified_action_args(kwargs, toolchain_tools)
  actions.run(**modified_args)

def _run_shell_action(toolchain_tools, actions, **kwargs):
  """Runs a shell action with the toolchain requirements.

  This is the implementation of the `action_registrars.run_shell` partial, where
  the first argument is pre-bound to a toolchain-specific value.

  Args:
    toolchain_tools: A `depset` containing toolchain files that must be
        available to the action when it executes (executables and libraries).
    actions: The `Actions` object with which to register actions.
    **kwargs: Additional arguments that are passed to `actions.run_shell`.
  """
  modified_args = _modified_action_args(kwargs, toolchain_tools)
  actions.run_shell(**modified_args)

def _swift_toolchain_impl(ctx):
  toolchain_root = ctx.attr.root
  cc_toolchain = ctx.attr._cc_toolchain[cc_common.CcToolchainInfo]

  linker_opts_producer = partial.make(
      _default_linker_opts, ctx.fragments.cpp, ctx.attr.os, toolchain_root)

  tools = depset(transitive=[ctx.attr._cc_toolchain.files])
  action_registrars = struct(
      run=partial.make(_run_action, tools),
      run_shell=partial.make(_run_shell_action, tools))

  # TODO(allevato): Move some of the remaining hardcoded values, like object
  # format, autolink-extract, and Obj-C interop support, to attributes so that
  # we can remove the assumptions that are only valid on Linux.
  return [
      SwiftToolchainInfo(
          action_environment={},
          action_registrars=action_registrars,
          cc_toolchain_info=cc_toolchain,
          clang_executable=ctx.attr.clang_executable,
          cpu=ctx.attr.arch,
          execution_requirements={},
          implicit_deps=[],
          linker_opts_producer=linker_opts_producer,
          object_format="elf",
          requires_autolink_extract=True,
          root_dir=toolchain_root,
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
        "clang_executable": attr.string(
            doc="""
The path to the `clang` executable, which is used for linking.
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
