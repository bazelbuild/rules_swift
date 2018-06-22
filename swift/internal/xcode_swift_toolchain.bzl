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

"""BUILD rules used to provide a Swift toolchain provided by Xcode on macOS.

The rules defined in this file are not intended to be used outside of the Swift
toolchain package. If you are looking for rules to build Swift code using this
toolchain, see `swift.bzl`.
"""

load(":providers.bzl", "SwiftToolchainInfo")
load("@bazel_skylib//:lib.bzl", "dicts", "partial")

def _default_linker_opts(
    apple_fragment,
    apple_toolchain,
    platform,
    target,
    is_static,
    is_test):
  """Returns options that should be passed by default to `clang` when linking.

  This function is wrapped in a `partial` that will be propagated as part of the
  toolchain provider. The first four arguments are pre-bound; the `is_static`
  and `is_test` arguments are expected to be passed by the caller.

  Args:
    apple_fragment: The `apple` configuration fragment.
    apple_toolchain: The `apple_common.apple_toolchain()` object.
    platform: The `apple_platform` value describing the target platform.
    target: The target triple.
    is_static: `True` to link against the static version of the Swift runtime,
        or `False` to link against dynamic/shared libraries.
    is_test: `True` if the target being linked is a test target.

  Returns:
    The command line options to pass to `clang` to link against the desired
    variant of the Swift runtime libraries.
  """
  platform_framework_dir = apple_toolchain.platform_developer_framework_dir(
      apple_fragment)

  linkopts = []

  if is_static:
    swift_subdir = "swift_static"
    linkopts.extend([
        "-Xlinker",
        "-force_load_swift_libs",
        "-framework",
        "Foundation",
        "-lstdc++",
    ])
  else:
    swift_subdir = "swift"

  swift_lib_dir = (
      "{developer_dir}/Toolchains/{toolchain}.xctoolchain" +
      "/usr/lib/{swift_subdir}/{platform}"
  ).format(
      developer_dir=apple_toolchain.developer_dir(),
      platform=platform.name_in_plist.lower(),
      swift_subdir=swift_subdir,
      toolchain="XcodeDefault",
  )

  linkopts.extend([
      "-target", target,
      "--sysroot", apple_toolchain.sdk_dir(),
      "-F", platform_framework_dir,
      "-L", swift_lib_dir,
  ])

  # XCTest.framework only lives in the Xcode bundle (its platform framework
  # directory), so test binaries need to have that directory explicitly added to
  # their rpaths.
  if is_test:
    linkopts.append("-Wl,-rpath,{}".format(platform_framework_dir))

  return linkopts

def _default_swiftc_copts(apple_fragment, apple_toolchain, target):
  """Returns options that should be passed by default to `swiftc`.

  Args:
    apple_fragment: The `apple` configuration fragment.
    apple_toolchain: The `apple_common.apple_toolchain()` object.
    target: The target triple.

  Returns:
    A list of options that will be passed to any compile action created by this
    toolchain.
  """
  copts = [
      "-target", target,
      "-sdk", apple_toolchain.sdk_dir(),
      "-F", apple_toolchain.platform_developer_framework_dir(apple_fragment),
  ]

  bitcode_mode = str(apple_fragment.bitcode_mode)
  if bitcode_mode == "embedded":
    copts.append("-embed-bitcode")
  elif bitcode_mode == "embedded_markers":
    copts.append("-embed-bitcode-marker")
  elif bitcode_mode != "none":
    fail("Internal error: expected apple_fragment.bitcode_mode to be one " +
         "of: ['embedded', 'embedded_markers', 'none']")

  return copts

def _is_macos(platform):
  """Returns `True` if the given platform is macOS.

  Args:
    platform: An `apple_platform` value describing the platform for which a
        target is being built.

  Returns:
    `True` if the given platform is macOS.
  """
  return platform.platform_type == apple_common.platform_type.macos

def _swift_apple_target_triple(cpu, platform, version):
  """Returns a target triple string for an Apple platform.

  Args:
    cpu: The CPU of the target.
    platform: The `apple_platform` value describing the target platform.
    version: The target platform version as a dotted version string.

  Returns:
    A target triple string describing the platform.
  """
  platform_string = str(platform.platform_type)
  if platform_string == "macos":
    platform_string = "macosx"

  return "{cpu}-apple-{platform}{version}".format(
      cpu=cpu,
      platform=platform_string,
      version=version,
  )

def _xcode_env(xcode_config, platform):
  """Returns a dictionary containing Xcode-related environment variables.

  Args:
    xcode_config: The `XcodeVersionConfig` provider that contains information
        about the current Xcode configuration.
    platform: The `apple_platform` value describing the target platform being
        built.

  Returns:
    A `dict` containing Xcode-related environment variables that should be
    passed to Swift compile and link actions.
  """
  return dicts.add(
      apple_common.apple_host_system_env(xcode_config),
      apple_common.target_apple_env(xcode_config, platform)
  )

def _xcode_swift_toolchain_impl(ctx):
  apple_fragment = ctx.fragments.apple
  apple_toolchain = apple_common.apple_toolchain()

  cpu = apple_fragment.single_arch_cpu
  platform = apple_fragment.single_arch_platform
  xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]

  target_os_version = xcode_config.minimum_os_for_platform_type(
      platform.platform_type)
  target = _swift_apple_target_triple(cpu, platform, target_os_version)

  linker_opts_producer = partial.make(
      _default_linker_opts, apple_fragment, apple_toolchain, platform, target)
  swiftc_copts = _default_swiftc_copts(apple_fragment, apple_toolchain, target)

  return [
      SwiftToolchainInfo(
          action_environment=_xcode_env(xcode_config, platform),
          cc_toolchain_info=None,
          cpu=cpu,
          execution_requirements={"requires-darwin": ""},
          implicit_deps=[],
          linker_opts_producer=linker_opts_producer,
          object_format="macho",
          requires_autolink_extract=False,
          requires_workspace_relative_module_maps=False,
          root_dir=None,
          spawn_wrapper=ctx.executable._xcrunwrapper,
          stamp=ctx.attr.stamp if _is_macos(platform) else None,
          supports_objc_interop=True,
          swiftc_copts=swiftc_copts,
          system_name="darwin",
      ),
  ]

xcode_swift_toolchain = rule(
    attrs={
        "stamp": attr.label(
            doc="""
A `cc`-providing target that should be linked into any binaries that are built
with stamping enabled.
""",
            providers=[["cc"]],
        ),
        "_xcode_config": attr.label(
            default=configuration_field(
                fragment="apple",
                name="xcode_config_label",
            ),
        ),
        "_xcrunwrapper": attr.label(
            cfg="host",
            default=Label("@bazel_tools//tools/objc:xcrunwrapper"),
            executable=True,
        ),
    },
    doc="Represents a Swift compiler toolchain provided by Xcode.",
    fragments=["apple", "cpp"],
    implementation=_xcode_swift_toolchain_impl,
)
