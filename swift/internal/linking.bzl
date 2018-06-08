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

"""Implementation of linking logic for Swift."""

load(":deps.bzl", "swift_deps_libraries")
load(":providers.bzl", "SwiftInfo", "SwiftToolchainInfo")
load(":utils.bzl", "collect_transitive")

def register_link_action(
    actions,
    action_environment,
    clang_executable,
    deps,
    execution_requirements,
    expanded_linkopts,
    features,
    inputs,
    mnemonic,
    objects,
    outputs,
    rule_specific_args,
    spawn_wrapper,
    toolchain_target):
  """Registers an action that invokes `clang` to link object files.

  Args:
    actions: The object used to register actions.
    action_environment: A `dict` of environment variables that should be set for
        the compile action.
    clang_executable: The path to the `clang` executable that will be invoked to
        link, which is assumed to be present among the files belonging to
        `toolchain_target`. If this is `None`, then simply `clang` will be used
        with the assumption that the spawn wrapper will ensure it is found.
    deps: A list of `deps` representing additional libraries that will be passed
        to the linker.
    execution_requirements: A `dict` of execution requirements for the
        registered actions.
    expanded_linkopts: A list of strings representing options passed to the
        linker. Any `$(location ...)` placeholders are assumed to have already
        been expanded.
    features: The list of features that are set on the target being linked.
    inputs: A `depset` containing additional inputs to the link action, such
        as those used in `$(location ...)` substitution, or libraries that need
        to be linked.
    mnemonic: The mnemonic printed by Bazel when the action executes.
    objects: A list of object (.o) files that will be passed to the linker.
    outputs: A list of `File`s that should be passed as the outputs of the
        link action.
    rule_specific_args: Additional arguments that are rule-specific that will be
        passed to `clang`.
    spawn_wrapper: An executable that will be used to wrap the invoked `clang`
        command line.
    toolchain_target: The `swift_toolchain` target representing the toolchain
        that should be used to compile this target.
  """
  toolchain = toolchain_target[SwiftToolchainInfo]

  wrapper_args = actions.args()

  # TODO(bazelbuild/rules_swift#10): Have the repository rule provide the
  # absolute file system path for clang.
  if not clang_executable or clang_executable.endswith("/gcc"):
    clang_executable = "clang"

  if spawn_wrapper:
    executable = spawn_wrapper
    wrapper_args.add(clang_executable)
  else:
    executable = clang_executable

  common_args = actions.args()
  if "llvm_lld" in features:
    common_args.add("-fuse-ld=lld")

  if toolchain.stamp:
    stamp_lib_depsets = [toolchain.stamp.cc.libs]
  else:
    stamp_lib_depsets = []

  libraries = depset(
      transitive=swift_deps_libraries(deps) + stamp_lib_depsets,
      order="topological")
  link_input_depsets = [
      libraries,
      inputs,
      collect_transitive(deps, SwiftInfo, "transitive_additional_inputs"),
  ]

  link_input_args = actions.args()
  link_input_args.set_param_file_format("multiline")
  link_input_args.use_param_file("@%s", use_always=True)

  if toolchain.root_dir:
    runtime_object_path = "{root}/lib/swift/{system}/{cpu}/swiftrt.o".format(
        cpu=toolchain.cpu,
        root=toolchain.root_dir,
        system=toolchain.system_name,
    )
    link_input_args.add(runtime_object_path)

  link_input_args.add(objects)
  link_input_args.add(libraries, map_fn=_link_library_map_fn)

  # TODO(b/70228246): Also support fully-dynamic mode.
  if toolchain.cc_toolchain_info:
    link_input_args.add("-static-libgcc")
    link_input_args.add("-lrt")
    link_input_args.add("-ldl")

  toolchain_args = actions.args()
  toolchain_args.add(toolchain.linker_opts)

  all_linkopts = depset(
      direct=expanded_linkopts,
      transitive=[
          dep[SwiftInfo].transitive_linkopts for dep in deps if SwiftInfo in dep
      ] + [
          depset(direct=dep.cc.link_flags) for dep in deps if hasattr(dep, "cc")
      ],
  ).to_list()

  # Workaround that removes a linker option that breaks swift binaries.
  # TODO(b/77640204): Remove this workaround.
  enable_text_relocation_linkopt = "-Wl,-z,notext"
  if enable_text_relocation_linkopt in all_linkopts:
    all_linkopts.remove(enable_text_relocation_linkopt)

  user_args = actions.args()
  user_args.add(all_linkopts)

  actions.run(
      arguments=[
          wrapper_args,
          common_args,
          link_input_args,
          rule_specific_args,
          toolchain_args,
          user_args,
      ],
      env=action_environment,
      executable=executable,
      execution_requirements=execution_requirements,
      inputs=depset(
          direct=objects,
          transitive=link_input_depsets + [toolchain_target.files],
      ),
      mnemonic=mnemonic,
      outputs=outputs,
      # TODO(bazelbuild/rules_swift#10): Use the shell's environment if a
      # custom one hasn't been provided to ensure "clang" is found until this
      # issue is resolved.
      use_default_shell_env=(not action_environment),
  )

def _link_library_map_fn(libs):
  """Maps a list of libraries to the appropriate flags to link them.

  This function handles `alwayslink` (.lo) libraries correctly by surrounding
  them with `--(no-)whole-archive`.

  Args:
    libs: A list of `File`s, passed in when the calling `Args` object is ready
        to map them to arguments.

  Returns:
    A list of command-line arguments (strings) that link the library correctly.
  """
  return [
      "-Wl,--whole-archive,{lib},--no-whole-archive".format(lib=lib.path)
      if lib.basename.endswith(".lo") else lib.path for lib in libs
  ]
