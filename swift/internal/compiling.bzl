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

"""Implementation of compilation logic for Swift."""

load(":attrs.bzl", "SWIFT_COMMON_RULE_ATTRS")
load(":deps.bzl", "swift_deps_libraries")
load(":derived_files.bzl", "derived_files")
load(
    ":providers.bzl",
    "SwiftClangModuleInfo",
    "SwiftInfo",
    "SwiftToolchainInfo",
)
load(":swift_cc_libs_aspect.bzl", "swift_cc_libs_excluding_directs_aspect")
load(":utils.bzl", "collect_transitive", "run_with_optional_wrapper")
load("@bazel_skylib//:lib.bzl", "collections", "dicts", "paths")

# Swift compiler options that cause the code to be compiled using whole-module
# optimization.
_WMO_COPTS = (
    "-force-single-frontend-invocation",
    "-whole-module-optimization",
    "-wmo",
)

SWIFT_TOOLCHAIN_ATTRS = {
    "_toolchain": attr.label(
        default=Label(
            "@build_bazel_rules_swift_local_config//:toolchain",
        ),
        providers=[[SwiftToolchainInfo]],
    ),
}

# Attributes shared by all rules that perform Swift compilation (swift_library,
# swift_core_library, swift_binary).
SWIFT_COMPILE_RULE_ATTRS = dicts.add(
    SWIFT_COMMON_RULE_ATTRS,
    SWIFT_TOOLCHAIN_ATTRS,
    {
        "cc_libs": attr.label_list(
            aspects=[swift_cc_libs_excluding_directs_aspect],
            doc="""
A list of `cc_library` targets that should be *merged* with the static library
or binary produced by this target.

Most normal Swift use cases do not need to make use of this attribute. It is
intended to support cases where C and Swift code *must* exist in the same
archive; for example, a Swift function annotated with `@_cdecl` which is then
referenced from C code in the same library.
""",
            providers=[["cc"]],
        ),
        "copts": attr.string_list(
            doc="""
Additional compiler options that should be passed to `swiftc`. These strings are
subject to `$(location ...)` expansion.
""",
        ),
        "defines": attr.string_list(
            doc="""
A list of defines to add to the compilation command line.

Note that unlike C-family languages, Swift defines do not have values; they are
simply identifiers that are either defined or undefined. So strings in this list
should be simple identifiers, **not** `name=value` pairs.

Each string is prepended with `-D` and added to the command line. Unlike
`copts`, these flags are added for the target and every target that depends on
it, so use this attribute with caution. It is preferred that you add defines
directly to `copts`, only using this feature in the rare case that a library
needs to propagate a symbol up to those that depend on it.
""",
        ),
        "linkopts": attr.string_list(
            doc="""
Additional linker options that should be passed to the linker for the binary
that depends on this target. These strings are subject to `$(location ...)`
expansion.
""",
        ),
        "module_name": attr.string(
            doc="""
The name of the Swift module being built.

If left unspecified, the module name will be computed based on the target's
build label, by stripping the leading `//` and replacing `/`, `:`, and other
non-identifier characters with underscores.
""",
        ),
        "srcs": attr.label_list(
            allow_files=["swift"],
            doc="""
A list of `.swift` source files that will be compiled into the library.
""",
        ),
        "swiftc_inputs": attr.label_list(
            allow_files=True,
            doc="""
Additional files that are referenced using `$(location ...)` in attributes that
support location expansion.
""",
        ),
    }
)

def build_swift_info_provider(
    additional_cc_libs,
    compile_options,
    deps,
    direct_additional_inputs,
    direct_defines,
    direct_libraries,
    direct_linkopts,
    direct_swiftmodules,
    module_name=None,
    swift_version=None):
  """Builds a `SwiftInfo` provider from direct outputs and dependencies.

  This logic is shared by both `swift_library` and `swift_import`.

  Args:
    additional_cc_libs: A list of additional `cc_library` dependencies whose
        libraries and linkopts need to be propagated by `SwiftInfo`.
    compile_options: A list of `Args` objects that contain the compilation
        options passed to `swiftc` to compile this target.
    deps: A list of dependencies of the target being built, which provide
        `SwiftInfo` providers.
    direct_additional_inputs: A list of additional input files passed into a
        library or binary target via the `swiftc_inputs` attribute.
    direct_defines: A list of defines that will be provided as `copts` of the
        target being built.
    direct_libraries: A list of `.a` files that are the direct outputs of the
        target being built.
    direct_linkopts: A list of linker flags that will be passed to the linker
        when the target being built is linked into a binary.
    direct_swiftmodules: A list of `.swiftmodule` files that are the direct
        outputs of the target being built.
    module_name: A string containing the name of the Swift module.
    swift_version: A string containing the value of the `-swift-version` flag
        used when compiling this target, or `None` if it was not set or is not
        relevant.

  Returns:
    A new `SwiftInfo` provider that propagates the direct and transitive
    libraries and modules for the target being built.
  """
  transitive_additional_inputs = collect_transitive(
      deps,
      SwiftInfo,
      "transitive_additional_inputs",
      direct=direct_additional_inputs,
  )
  transitive_defines = collect_transitive(
      deps, SwiftInfo, "transitive_defines", direct=direct_defines)

  # Note that we also collect the transitive libraries and linker flags from
  # cc_library deps and propagate them through the Swift provider; this is
  # necessary because we cannot construct our own CcSkylarkApiProviders from
  # within Skylark; only consume them.
  transitive_libraries = depset(
      direct=direct_libraries,
      transitive=swift_deps_libraries(deps + additional_cc_libs),
      order="topological",
  )
  transitive_linkopts = depset(
      direct=direct_linkopts,
      transitive=[
          dep[SwiftInfo].transitive_linkopts for dep in deps if SwiftInfo in dep
      ] + [
          depset(direct=dep.cc.link_flags) for dep in deps if hasattr(dep, "cc")
      ] + [
          depset(direct=lib.cc.link_flags) for lib in additional_cc_libs
      ],
  )
  transitive_swiftmodules = collect_transitive(
      deps, SwiftInfo, "transitive_swiftmodules", direct=direct_swiftmodules)

  return SwiftInfo(
      compile_options=compile_options,
      direct_defines=direct_defines,
      direct_libraries=direct_libraries,
      direct_linkopts=direct_linkopts,
      direct_swiftmodules=direct_swiftmodules,
      module_name=module_name,
      swift_version=swift_version,
      transitive_additional_inputs=transitive_additional_inputs,
      transitive_defines=transitive_defines,
      transitive_libraries=transitive_libraries,
      transitive_linkopts=transitive_linkopts,
      transitive_swiftmodules=transitive_swiftmodules,
  )

def collect_transitive_compile_inputs(args, deps, direct_defines=[]):
  """Collect transitive inputs and flags from Swift providers.

  Args:
    args: An `Args` object to which
    deps: The dependencies for which the inputs should be gathered.
    direct_defines: The list of defines for the target being built, which are
        merged with the transitive defines before they are added to `args` in
        order to prevent duplication.

  Returns:
    A list of `depset`s representing files that must be passed as inputs to the
    Swift compilation action.
  """
  input_depsets = []

  # Collect all the search paths, module maps, flags, and so forth from
  # transitive dependencies.
  transitive_swiftmodules = collect_transitive(
      deps, SwiftInfo, "transitive_swiftmodules")
  args.add_all(transitive_swiftmodules, before_each="-I", map_each=_dirname_map_fn)
  input_depsets.append(transitive_swiftmodules)

  transitive_defines = collect_transitive(
      deps, SwiftInfo, "transitive_defines", direct=direct_defines)
  args.add_all(transitive_defines, format_each="-D%s")

  transitive_modulemaps = collect_transitive(
      deps, SwiftClangModuleInfo, "transitive_modulemaps")
  input_depsets.append(transitive_modulemaps)
  args.add_all(transitive_modulemaps,
           before_each="-Xcc", format_each="-fmodule-map-file=%s")

  transitive_cc_headers = collect_transitive(
      deps, SwiftClangModuleInfo, "transitive_headers")
  input_depsets.append(transitive_cc_headers)

  transitive_cc_compile_flags = collect_transitive(
      deps, SwiftClangModuleInfo, "transitive_compile_flags")
  # Handle possible spaces in these arguments correctly (for example,
  # `-isystem foo`) by prepending `-Xcc` to each one.
  for arg in transitive_cc_compile_flags.to_list():
    args.add_all(arg.split(" "), before_each="-Xcc")

  transitive_cc_defines = collect_transitive(
      deps, SwiftClangModuleInfo, "transitive_defines")
  args.add_all(transitive_cc_defines, before_each="-Xcc", format_each="-D%s")

  return input_depsets

def declare_compile_outputs(
    actions,
    copts,
    features,
    srcs,
    target_name):
  """Declares output files (and optional output file map) for a compile action.

  Args:
    actions: The object used to register actions.
    copts: The flags that will be passed to the compile action, which are
        scanned to determine whether a single frontend invocation will be used
        or not.
    features: Features that are enabled for the target being built.
    srcs: The list of source files that will be compiled.
    target_name: The name (excluding package path) of the target being built.

  Returns:
    A `struct` containing the following fields:

    * `args`: A list of values that should be added to the `Args` of the compile
      action.
    * `compile_inputs`: Additional input files that should be passed to the
      compile action.
    * `other_outputs`: Additional output files that should be declared by the
      compile action, but which are not processed further.
    * `output_groups`: A dictionary of additional output groups that should be
      propagated by the calling rule using the `OutputGroupInfo` provider.
    * `output_objects`: A list of object (.o) files that will be the result of
      the compile action and which should be archived afterward.
  """
  if _emits_single_object(copts):
    # If we're emitting a single object, we don't use an object map; we just
    # declare the output file that the compiler will generate and there are no
    # other partial outputs.
    out_obj = derived_files.whole_module_object_file(
        actions, target_name=target_name)
    return struct(
        args=["-o", out_obj],
        compile_inputs=[],
        other_outputs=[],
        output_groups={},
        output_objects=[out_obj],
    )

  # Otherwise, we need to create an output map that lists the individual object
  # files so that we can pass them all to the archive action.
  output_map_file = derived_files.swiftc_output_file_map(
      actions, target_name=target_name)

  # The output map data, which is keyed by source path and will be written to
  # output_map_file.
  output_map = {}
  # Object files that will be used to build the archive.
  output_objs = []
  # Additional files, such as partial Swift modules, that must be declared as
  # action outputs although they are not processed further.
  other_outputs = []

  for src in srcs:
    # Declare the object file and partial .swiftmodule corresponding to the
    # source file.
    obj = derived_files.intermediate_object_file(
        actions, target_name=target_name, src=src)
    output_objs.append(obj)

    partial_module = derived_files.partial_swiftmodule(
        actions, target_name=target_name, src=src)
    other_outputs.append(partial_module)

    output_map[src.path] = struct(
        object=obj.path,
        swiftmodule=partial_module.path,
    )

  actions.write(
      content=struct(**output_map).to_json(),
      output=output_map_file,
  )

  args = ["-output-file-map", output_map_file]
  output_groups = {}

  # Configure index-while-building if the feature is enabled. IDEs and other
  # indexing tools can enable this feature on the command line during a build
  # and then access the index store artifacts that are produced.
  if "swift.index_while_building" in features:
    index_store_dir = derived_files.indexstore_directory(
        actions, target_name=target_name)
    other_outputs.append(index_store_dir)
    args.extend(["-index-store-path", index_store_dir.path])
    output_groups["swift_index_store"] = depset(direct=[index_store_dir])

  return struct(
      args=args,
      compile_inputs=[output_map_file],
      other_outputs=other_outputs,
      output_groups=output_groups,
      output_objects=output_objs,
  )

def find_swift_version_copt_value(copts):
  """Returns the value of the `-swift-version` argument, if found.

  Args:
    copts: The list of copts to be scanned.

  Returns:
    The value of the `-swift-version` argument, or None if it was not found in
    the copt list.
  """
  # Note that the argument can occur multiple times, and the last one wins.
  last_swift_version = None

  count = len(copts)
  for i in range(count):
    copt = copts[i]
    if copt == "-swift-version" and i + 1 < count:
      last_swift_version = copts[i + 1]

  return last_swift_version

def new_objc_provider(
    deps,
    include_path,
    link_inputs,
    linkopts,
    module_map,
    objc_header,
    static_archive,
    swiftmodule):
  """Creates an `apple_common.Objc` provider for a Swift target.

  Args:
    deps: The dependencies of the target being built, whose `Objc` providers
        will be passed to the new one in order to propagate the correct
        transitive fields.
    include_path: A header search path that should be propagated to dependents.
    link_inputs: Additional linker input files that should be propagated to
        dependents.
    linkopts: Linker options that should be propagated to dependents.
    module_map: The module map generated for the Swift target's Objective-C
        header, if any.
    objc_header: The generated Objective-C header for the Swift target.
    static_archive: The static archive (`.a` file) containing the target's
        compiled code.
    swiftmodule: The `.swiftmodule` file for the compiled target.

  Returns:
    An `apple_common.Objc` provider that should be returned by the calling rule.
  """
  objc_providers = [dep[apple_common.Objc] for dep in deps
                    if apple_common.Objc in dep]
  objc_provider_args = {
      "header": depset(direct=[objc_header]),
      "include": depset(direct=[include_path]),
      "library": depset(direct=[static_archive]),
      "link_inputs": depset(direct=[swiftmodule] + link_inputs),
      "linkopt": depset(direct=linkopts),
      "providers": objc_providers,
      "uses_swift": True,
  }

  # In addition to the generated header's module map, we must re-propagate the
  # direct deps' Objective-C module maps to dependents, because those Swift
  # modules still need to see them. We need to construct a new transitive objc
  # provider to get the correct strict propagation behavior.
  transitive_objc_provider_args = {"providers": objc_providers}
  if module_map:
    transitive_objc_provider_args["module_map"] = (
        depset(direct=[module_map]))
  transitive_objc = apple_common.new_objc_provider(
      **transitive_objc_provider_args)
  objc_provider_args["module_map"] = transitive_objc.module_map

  return apple_common.new_objc_provider(**objc_provider_args)

def objc_compile_requirements(args, deps, objc_fragment):
  """Collects compilation requirements for Objective-C dependencies.

  Args:
    args: An `Args` object to which compile options will be added.
    deps: The `deps` of the target being built.
    objc_fragment: The `objc` configuration fragment.

  Returns:
    A `depset` of files that should be included among the inputs of the compile
    action.
  """
  defines = []
  includes = []
  inputs = []
  module_maps = []
  static_frameworks = []
  all_frameworks = []

  objc_providers = [dep[apple_common.Objc] for dep in deps
                    if apple_common.Objc in dep]

  for objc in objc_providers:
    inputs.append(objc.header)
    inputs.append(objc.umbrella_header)
    inputs.append(objc.static_framework_file)
    inputs.append(objc.dynamic_framework_file)

    inputs.append(objc.module_map)
    module_maps.append(objc.module_map)

    defines.append(objc.define)
    includes.append(objc.include)

    static_frameworks.append(objc.framework_dir)
    all_frameworks.append(objc.framework_dir)
    all_frameworks.append(objc.dynamic_framework_dir)

  # Add the objc dependencies' header search paths so that imported modules can
  # find their headers.
  args.add(depset(transitive=includes), format="-I%s")

  # Add framework search paths for any Objective-C frameworks propagated through
  # static/dynamic framework provider keys.
  args.add(depset(transitive=all_frameworks),
           format="-F%s", map_fn=_parent_dirs)

  # Disable the `LC_LINKER_OPTION` load commands for static framework automatic
  # linking. This is needed to correctly deduplicate static frameworks from also
  # being linked into test binaries where it is also linked into the app binary.
  # TODO(allevato): Update this to not expand the depset once `Args.add`
  # supports returning multiple elements from a `map_fn`.
  for framework in depset(transitive=static_frameworks).to_list():
    args.add(collections.before_each(
        "-Xfrontend", [
            "-disable-autolink-framework",
            _objc_provider_framework_name(framework),
        ],
    ))

  # Swift's ClangImporter does not include the current directory by default in
  # its search paths, so we must add it to find workspace-relative imports in
  # headers imported by module maps.
  args.add(collections.before_each("-Xcc", ["-iquote", "."]))

  # Ensure that headers imported by Swift modules have the correct defines
  # propagated from dependencies.
  args.add(depset(transitive=defines), before_each="-Xcc", format="-D%s")

  # Load module maps explicitly instead of letting Clang discover them in the
  # search paths. This is needed to avoid a case where Clang may load the same
  # header in modular and non-modular contexts, leading to duplicate definitions
  # in the same file. <https://llvm.org/bugs/show_bug.cgi?id=19501>
  args.add(depset(transitive=module_maps),
           before_each="-Xcc", format="-fmodule-map-file=%s")

  # Add any copts required by the `objc` configuration fragment.
  args.add(_clang_copts(objc_fragment), before_each="-Xcc")

  return depset(transitive=inputs)

def register_autolink_extract_action(
    actions,
    objects,
    output,
    toolchain_target):
  """Extracts autolink information from Swift `.o` files.

  For some platforms (such as Linux), autolinking of imported frameworks is
  achieved by extracting the information about which libraries are needed from
  the `.o` files and producing a text file with the necessary linker flags. That
  file can then be passed to the linker as a response file (i.e., `@flags.txt`).

  Args:
    actions: The object used to register actions.
    objects: The list of object files whose autolink information will be
        extracted.
    output: A `File` into which the autolink information will be written.
    toolchain_target: The `swift_toolchain` target representing the toolchain
        that should be used.
  """
  toolchain = toolchain_target[SwiftToolchainInfo]

  tool_args = actions.args()
  tool_args.add(objects)
  tool_args.add("-o")
  tool_args.add(output)

  run_with_optional_wrapper(
      actions=actions,
      arguments=[tool_args],
      env=toolchain.action_environment,
      executable_name="swift-autolink-extract",
      execution_requirements=toolchain.execution_requirements,
      inputs = depset(
          direct=objects,
          transitive=[toolchain_target.files],
      ),
      mnemonic="SwiftAutolinkExtract",
      outputs=[output],
      toolchain_root=toolchain.root_dir,
      wrapper_executable=toolchain.spawn_wrapper,
  )

def swift_library_output_map(name, module_link_name):
  """Returns the dictionary of implicit outputs for a `swift_library`.

  This function is used to specify the `outputs` of the `swift_library` rule; as
  such, its arguments must be named exactly the same as the attributes to which
  they refer.

  Args:
    name: The name of the target being built.
    module_link_name: The module link name of the target being built.

  Returns:
    The implicit outputs dictionary for a `swift_library`.
  """
  lib_name = module_link_name if module_link_name else name
  return {
      "archive": "lib{}.a".format(lib_name),
  }

def write_objc_header_module_map(
    actions,
    module_name,
    objc_header,
    output):
  """Writes a module map for a generated Swift header to a file.

  Args:
    actions: The context's actions object.
    module_name: The name of the Swift module.
    objc_header: The `File` representing the generated header.
    output: The `File` to which the module map should be written.
  """
  actions.write(
      content=('module "{module_name}" {{\n' +
               '  header "../{header_name}"\n' +
               '}}\n').format(
                   header_name=objc_header.basename,
                   module_name=module_name,
               ),
      output=output,
  )

def _clang_copts(objc_fragment):
  """Returns copts that should be passed to `clang` from the `objc` fragment.

  Args:
    objc_fragment: The `objc` configuration fragment.

  Returns:
    A list of `clang` copts.
  """
  # In general, every compilation mode flag from native `objc_*` rules should be
  # passed, but `-g` seems to break Clang module compilation. Since this flag
  # does not make much sense for module compilation and only touches headers,
  # it's ok to omit.
  clang_copts = (
      objc_fragment.copts + objc_fragment.copts_for_current_compilation_mode)
  return [copt for copt in clang_copts if copt != "-g"]

def _dirname_map_fn(f):
  """Returns the dir name of a file.

  This function is intended to be used as a mapping function for file passed
  into `Args.add`.

  Args:
    f: The file

  Returns:
    The dirname of the file
  """
  return f.dirname

def _emits_single_object(copts):
  """Returns `True` if the compiler emits a single object for the given flags.

  The compiler emits a single object if it is invoked with whole-module
  optimization enabled and is single-threaded (`-num-threads` is not present or
  is equal to 1).

  Args:
    copts: The options passed into the compile action.

  Returns:
    `True` if the given copts cause the compiler to emit a single object file.
  """
  is_wmo = False
  saw_space_separated_num_threads = False
  num_threads = 1

  for copt in copts:
    if copt in _WMO_COPTS:
      is_wmo = True
    elif saw_space_separated_num_threads:
      num_threads = int(copt)
    elif copt == "-num-threads":
      saw_space_separated_num_threads = True
    elif copt.startswith("-num-threads="):
      num_threads = copt.split("=")[1]

  return is_wmo and num_threads == 1

def _objc_provider_framework_name(path):
  """Returns the name of the framework from an `objc` provider path.

  Args:
    path: A path that came from an `objc` provider.

  Returns:
    A string containing the name of the framework (e.g., `Foo` for
    `Foo.framework`).
  """
  return path.rpartition("/")[2].partition(".")[0]

def _parent_dirs(path_list):
  """Returns the parent directory of the given paths.

  Args:
    path_list: A list of strings representing file paths.

  Returns:
    A list of strings containing the parent directories of the given paths.
  """
  return [paths.dirname(path) for path in path_list]
