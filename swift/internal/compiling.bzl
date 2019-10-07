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

load("@bazel_skylib//lib:collections.bzl", "collections")
load("@bazel_skylib//lib:paths.bzl", "paths")
load(
    "@build_bazel_apple_support//lib:framework_migration.bzl",
    "framework_migration",
)
load(":actions.bzl", "get_swift_tool", "run_swift_action")
load(":derived_files.bzl", "derived_files")
load(":providers.bzl", "SwiftInfo")
load(
    ":utils.bzl",
    "collect_cc_libraries",
    "get_providers",
    "objc_provider_framework_name",
)

def collect_transitive_compile_inputs(args, deps, direct_defines = []):
    """Collect transitive inputs and flags from Swift providers.

    Args:
        args: An `Args` object to which
        deps: The dependencies for which the inputs should be gathered.
        direct_defines: The list of defines for the target being built, which are merged with the
            transitive defines before they are added to `args` in order to prevent duplication.

    Returns:
        A list of `depset`s representing files that must be passed as inputs to the Swift
        compilation action.
    """
    input_depsets = []

    # Collect all the search paths, module maps, flags, and so forth from transitive dependencies.
    transitive_cc_defines = []
    transitive_cc_headers = []
    transitive_cc_includes = []
    transitive_cc_quote_includes = []
    transitive_cc_system_includes = []
    transitive_defines = []
    transitive_modulemaps = []
    transitive_swiftmodules = []
    for dep in deps:
        if SwiftInfo in dep:
            swift_info = dep[SwiftInfo]
            transitive_defines.append(swift_info.transitive_defines)
            transitive_modulemaps.append(swift_info.transitive_modulemaps)
            transitive_swiftmodules.append(swift_info.transitive_swiftmodules)
        if CcInfo in dep:
            compilation_context = dep[CcInfo].compilation_context
            transitive_cc_defines.append(compilation_context.defines)
            transitive_cc_headers.append(compilation_context.headers)
            transitive_cc_includes.append(compilation_context.includes)
            transitive_cc_quote_includes.append(compilation_context.quote_includes)
            transitive_cc_system_includes.append(compilation_context.system_includes)

    # Add import paths for the directories containing dependencies' swiftmodules.
    all_swiftmodules = depset(transitive = transitive_swiftmodules)
    args.add_all(all_swiftmodules, format_each = "-I%s", map_each = _dirname_map_fn)
    input_depsets.append(all_swiftmodules)

    # Pass Swift defines propagated by dependencies.
    all_defines = depset(direct_defines, transitive = transitive_defines)
    args.add_all(all_defines, format_each = "-D%s")

    # Pass module maps from C/C++ dependencies to ClangImporter.
    # TODO(allevato): Will `CcInfo` eventually keep these in its compilation context?
    all_modulemaps = depset(transitive = transitive_modulemaps)
    input_depsets.append(all_modulemaps)
    args.add_all(all_modulemaps, before_each = "-Xcc", format_each = "-fmodule-map-file=%s")

    # Add C++ headers from dependencies to the action inputs so the compiler can read them.
    input_depsets.append(depset(transitive = transitive_cc_headers))

    # Pass any C++ defines and include search paths to ClangImporter.
    args.add_all(
        depset(transitive = transitive_cc_defines),
        before_each = "-Xcc",
        format_each = "-D%s",
    )
    args.add_all(
        depset(transitive = transitive_cc_includes),
        before_each = "-Xcc",
        format_each = "-I%s",
    )
    args.add_all(
        depset(transitive = transitive_cc_quote_includes),
        before_each = "-Xcc",
        format_each = "-iquote%s",
    )
    args.add_all(
        depset(transitive = transitive_cc_system_includes),
        before_each = "-Xcc",
        format_each = "-isystem%s",
    )

    return input_depsets

def declare_compile_outputs(
        actions,
        copts,
        is_wmo,
        srcs,
        target_name,
        index_while_building = False):
    """Declares output files (and optional output file map) for a compile action.

    Args:
        actions: The object used to register actions.
        copts: The flags that will be passed to the compile action, which are scanned to determine
            whether a single frontend invocation will be used or not.
        is_wmo: Whether the compilation is happening with whole module optimization.
        srcs: The list of source files that will be compiled.
        target_name: The name (excluding package path) of the target being built.
        index_while_building: If `True`, a tree artifact will be declared to hold Clang index store
            data and the relevant option will be added during compilation to generate the indexes.

    Returns:
        A `struct` containing the following fields:

        *   `args`: A list of values that should be added to the `Args` of the compile action.
        *   `compile_inputs`: Additional input files that should be passed to the compile action.
        *   `indexstore`: A `File` representing the index store directory that was generated if
            index-while-building was enabled, or None.
        *   `other_outputs`: Additional output files that should be declared by the compile action,
            but which are not processed further.
        *   `output_groups`: A dictionary of additional output groups that should be propagated by
            the calling rule using the `OutputGroupInfo` provider.
        *   `output_objects`: A list of object (.o) files that will be the result of the compile
            action and which should be archived afterward.
    """
    output_nature = _emitted_output_nature(copts, is_wmo)

    if not output_nature.emits_multiple_objects:
        # If we're emitting a single object, we don't use an object map; we just declare the output
        # file that the compiler will generate and there are no other partial outputs.
        out_obj = derived_files.whole_module_object_file(actions, target_name = target_name)
        return struct(
            args = ["-o", out_obj],
            compile_inputs = [],
            # TODO(allevato): We need to handle indexing here too.
            indexstore = None,
            other_outputs = [],
            output_groups = {
                "compilation_outputs": depset(items = [out_obj]),
            },
            output_objects = [out_obj],
        )

    # Otherwise, we need to create an output map that lists the individual object files so that we
    # can pass them all to the archive action.
    output_map_file = derived_files.swiftc_output_file_map(actions, target_name = target_name)

    # The output map data, which is keyed by source path and will be written to `output_map_file`.
    output_map = {}

    # Object files that will be used to build the archive.
    output_objs = []

    # Additional files, such as partial Swift modules, that must be declared as action outputs
    # although they are not processed further.
    other_outputs = []

    for src in srcs:
        src_output_map = {}

        # Declare the object file (there is one per source file).
        obj = derived_files.intermediate_object_file(actions, target_name = target_name, src = src)
        output_objs.append(obj)
        src_output_map["object"] = obj.path

        # Multi-threaded WMO compiles still produce a single .swiftmodule file, despite producing
        # multiple object files, so we have to check explicitly for that case.
        if output_nature.emits_partial_modules:
            partial_module = derived_files.partial_swiftmodule(
                actions,
                target_name = target_name,
                src = src,
            )
            other_outputs.append(partial_module)
            src_output_map["swiftmodule"] = partial_module.path

        output_map[src.path] = struct(**src_output_map)

    # Output the module-wide `.swiftdeps` file, which is used for incremental builds.
    swiftdeps = derived_files.swift_dependencies_file(actions, target_name = target_name)
    other_outputs.append(swiftdeps)
    output_map[""] = {"swift-dependencies": swiftdeps.path}

    actions.write(
        content = struct(**output_map).to_json(),
        output = output_map_file,
    )

    args = ["-output-file-map", output_map_file]
    output_groups = {
        "compilation_outputs": depset(items = output_objs),
    }

    # Configure index-while-building if requested. IDEs and other indexing tools can enable this
    # feature on the command line during a build and then access the index store artifacts that are
    # produced.
    if index_while_building and not _index_store_path_overridden(copts):
        index_store_dir = derived_files.indexstore_directory(actions, target_name = target_name)
        other_outputs.append(index_store_dir)
        args.extend(["-index-store-path", index_store_dir.path])
        output_groups["swift_index_store"] = depset(direct = [index_store_dir])
    else:
        index_store_dir = None

    return struct(
        args = args,
        compile_inputs = [output_map_file],
        indexstore = index_store_dir,
        other_outputs = other_outputs,
        output_groups = output_groups,
        output_objects = output_objs,
    )

def find_swift_version_copt_value(copts):
    """Returns the value of the `-swift-version` argument, if found.

    Args:
        copts: The list of copts to be scanned.

    Returns:
        The value of the `-swift-version` argument, or None if it was not found in the copt list.
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
        static_archives,
        swiftmodules,
        defines = [],
        objc_header = None):
    """Creates an `apple_common.Objc` provider for a Swift target.

    Args:
        deps: The dependencies of the target being built, whose `Objc` providers will be passed to
            the new one in order to propagate the correct transitive fields.
        include_path: A header search path that should be propagated to dependents.
        link_inputs: Additional linker input files that should be propagated to dependents.
        linkopts: Linker options that should be propagated to dependents.
        module_map: The module map generated for the Swift target's Objective-C header, if any.
        static_archives: A list (typically of one element) of the static archives (`.a` files)
            containing the target's compiled code.
        swiftmodules: A list (typically of one element) of the `.swiftmodule` files for the
            compiled target.
        defines: A list of `defines` from the propagating `swift_library` that should also be
            defined for `objc_library` targets that depend on it.
        objc_header: The generated Objective-C header for the Swift target. If `None`, no headers
            will be propagated. This header is only needed for Swift code that defines classes that
            should be exposed to Objective-C.

    Returns:
        An `apple_common.Objc` provider that should be returned by the calling rule.
    """
    objc_providers = get_providers(deps, apple_common.Objc)
    objc_provider_args = {
        "link_inputs": depset(direct = swiftmodules + link_inputs),
        "providers": objc_providers,
        "uses_swift": True,
    }

    # The link action registered by `apple_binary` only looks at `Objc` providers, not `CcInfo`,
    # for libraries to link. Until that rule is migrated over, we need to collect libraries from
    # `CcInfo` (which will include Swift and C++) and put them into the new `Objc` provider.
    transitive_cc_libs = []
    for cc_info in get_providers(deps, CcInfo):
        static_libs = collect_cc_libraries(cc_info = cc_info, include_static = True)
        transitive_cc_libs.append(depset(static_libs, order = "topological"))
    objc_provider_args["library"] = depset(
        static_archives,
        transitive = transitive_cc_libs,
        order = "topological",
    )

    if include_path:
        objc_provider_args["include"] = depset(direct = [include_path])
    if defines:
        objc_provider_args["define"] = depset(direct = defines)
    if objc_header:
        objc_provider_args["header"] = depset(direct = [objc_header])
    if linkopts:
        objc_provider_args["linkopt"] = depset(direct = linkopts)

    force_loaded_libraries = [
        archive
        for archive in static_archives
        if archive.basename.endswith(".lo")
    ]
    if force_loaded_libraries:
        objc_provider_args["force_load_library"] = depset(direct = force_loaded_libraries)

    # In addition to the generated header's module map, we must re-propagate the direct deps'
    # Objective-C module maps to dependents, because those Swift modules still need to see them. We
    # need to construct a new transitive objc provider to get the correct strict propagation
    # behavior.
    transitive_objc_provider_args = {"providers": objc_providers}
    if module_map:
        transitive_objc_provider_args["module_map"] = depset(direct = [module_map])

    transitive_objc = apple_common.new_objc_provider(**transitive_objc_provider_args)
    objc_provider_args["module_map"] = transitive_objc.module_map

    return apple_common.new_objc_provider(**objc_provider_args)

def objc_compile_requirements(args, deps):
    """Collects compilation requirements for Objective-C dependencies.

    Args:
        args: An `Args` object to which compile options will be added.
        deps: The `deps` of the target being built.

    Returns:
        A `depset` of files that should be included among the inputs of the compile action.
    """
    defines = []
    includes = []
    inputs = []
    module_maps = []
    static_framework_names = []
    all_frameworks = []

    objc_providers = get_providers(deps, apple_common.Objc)

    post_framework_cleanup = framework_migration.is_post_framework_migration()

    for objc in objc_providers:
        inputs.append(objc.header)
        inputs.append(objc.umbrella_header)

        defines.append(objc.define)
        includes.append(objc.include)

        if post_framework_cleanup:
            static_framework_names.append(objc.static_framework_names)
            all_frameworks.append(objc.framework_search_path_only)
        else:
            inputs.append(objc.static_framework_file)
            inputs.append(objc.dynamic_framework_file)
            static_framework_names.append(depset(
                [objc_provider_framework_name(fdir) for fdir in objc.framework_dir.to_list()],
            ))
            all_frameworks.append(objc.framework_dir)
            all_frameworks.append(objc.dynamic_framework_dir)

    # Collect module maps for dependencies. These must be pulled from a combined transitive
    # provider to get the correct strict propagation behavior that we use to workaround command-line
    # length issues until Swift 4.2 is available.
    transitive_objc_provider = apple_common.new_objc_provider(providers = objc_providers)
    module_maps = transitive_objc_provider.module_map
    inputs.append(module_maps)

    # Add the objc dependencies' header search paths so that imported modules can find their
    # headers.
    args.add_all(depset(transitive = includes), format_each = "-I%s")

    # Add framework search paths for any prebuilt frameworks.
    args.add_all(
        depset(transitive = all_frameworks),
        format_each = "-F%s",
        map_each = paths.dirname,
    )

    # Disable the `LC_LINKER_OPTION` load commands for static framework automatic linking. This is
    # needed to correctly deduplicate static frameworks from also being linked into test binaries
    # where it is also linked into the app binary.
    args.add_all(
        depset(transitive = static_framework_names),
        map_each = _disable_autolink_framework_copts,
    )

    # Swift's ClangImporter does not include the current directory by default in its search paths,
    # so we must add it to find workspace-relative imports in headers imported by module maps.
    args.add_all(["-Xcc", "-iquote."])

    # Ensure that headers imported by Swift modules have the correct defines propagated from
    # dependencies.
    args.add_all(depset(transitive = defines), before_each = "-Xcc", format_each = "-D%s")

    # Take any Swift-compatible defines from Objective-C dependencies and define them for Swift.
    args.add_all(
        depset(transitive = defines),
        map_each = _exclude_swift_incompatible_define,
        format_each = "-D%s",
    )

    # Load module maps explicitly instead of letting Clang discover them in the search paths. This
    # is needed to avoid a case where Clang may load the same header in modular and non-modular
    # contexts, leading to duplicate definitions in the same file.
    # <https://llvm.org/bugs/show_bug.cgi?id=19501>
    args.add_all(module_maps, before_each = "-Xcc", format_each = "-fmodule-map-file=%s")

    return depset(transitive = inputs)

def output_groups_from_compilation_outputs(compilation_outputs):
    """Returns a dictionary of output groups from Swift compilation outputs.

    Args:
        compilation_outputs: The result of calling `swift_common.compile`.

    Returns:
        A `dict` whose keys are the names of output groups and values are
        `depset`s of `File`s, which can be splatted as keyword arguments to the
        `OutputGroupInfo` constructor.
    """
    output_groups = {}

    if compilation_outputs.indexstore:
        output_groups["swift_index_store"] = depset([
            compilation_outputs.indexstore,
        ])

    if compilation_outputs.stats_directory:
        output_groups["swift_compile_stats_direct"] = depset([
            compilation_outputs.stats_directory,
        ])

    if compilation_outputs.swiftinterface:
        output_groups["swiftinterface"] = depset([
            compilation_outputs.swiftinterface,
        ])

    return output_groups

def register_autolink_extract_action(
        actions,
        module_name,
        objects,
        output,
        toolchain):
    """Extracts autolink information from Swift `.o` files.

    For some platforms (such as Linux), autolinking of imported frameworks is achieved by extracting
    the information about which libraries are needed from the `.o` files and producing a text file
    with the necessary linker flags. That file can then be passed to the linker as a response file
    (i.e., `@flags.txt`).

    Args:
        actions: The object used to register actions.
        module_name: The name of the module to which the `.o` files belong (used when generating
            the progress message).
        objects: The list of object files whose autolink information will be extracted.
        output: A `File` into which the autolink information will be written.
        toolchain: The `SwiftToolchainInfo` provider of the toolchain.
    """
    args = actions.args()
    args.add(get_swift_tool(swift_toolchain = toolchain, tool = "swift-autolink-extract"))
    args.add_all(objects)
    args.add("-o", output)

    run_swift_action(
        actions = actions,
        arguments = [args],
        inputs = objects,
        mnemonic = "SwiftAutolinkExtract",
        outputs = [output],
        progress_message = "Extracting autolink data for Swift module {}".format(module_name),
        swift_toolchain = toolchain,
    )

def swift_library_output_map(name, alwayslink):
    """Returns the dictionary of implicit outputs for a `swift_library`.

    This function is used to specify the `outputs` of the `swift_library` rule; as such, its
    arguments must be named exactly the same as the attributes to which they refer.

    Args:
        name: The name of the target being built.
        alwayslink: Indicates whether the object files in the library should always
            be always be linked into any binaries that depend on it, even if some
            contain no symbols referenced by the binary.

    Returns:
        The implicit outputs dictionary for a `swift_library`.
    """
    extension = "lo" if alwayslink else "a"
    return {
        "archive": "lib{}.{}".format(name, extension),
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
        content = ('module "{module_name}" {{\n' +
                   '  header "../{header_name}"\n' +
                   "}}\n").format(
            header_name = objc_header.basename,
            module_name = module_name,
        ),
        output = output,
    )

def _index_store_path_overridden(copts):
    """Checks if index_while_building must be disabled.

    Index while building is disabled when the copts include a custom -index-store-path.

    Args:
        copts: The list of copts to be scanned.

    Returns:
        True if the index_while_building must be disabled, otherwise False.
    """
    for opt in copts:
        if opt == "-index-store-path":
            return True
    return False

def _dirname_map_fn(f):
    """Returns the dir name of a file.

    This function is intended to be used as a mapping function for file passed into `Args.add`.

    Args:
        f: The file.

    Returns:
        The dirname of the file.
    """
    return f.dirname

def _disable_autolink_framework_copts(framework_name):
    """A `map_each` helper that disables autolinking for the given framework.

    Args:
        framework_name: The name of the framework.

    Returns:
        The list of `swiftc` flags needed to disable autolinking for the given framework.
    """
    return collections.before_each(
        "-Xfrontend",
        [
            "-disable-autolink-framework",
            framework_name,
        ],
    )

def _emitted_output_nature(copts, is_wmo):
    """Returns a `struct` with information about the nature of emitted outputs for the given flags.

    The compiler emits a single object if it is invoked with whole-module optimization enabled and
    is single-threaded (`-num-threads` is not present or is equal to 1); otherwise, it emits one
    object file per source file. It also emits a single `.swiftmodule` file for WMO builds,
    _regardless of thread count,_ so we have to treat that case separately.

    Args:
        copts: The options passed into the compile action.
        is_wmo: Whether the compilation is happening with whole module optimization.

    Returns:
        A struct containing the following fields:

        *   `emits_multiple_objects`: `True` if the Swift frontend emits an object file per source
            file, instead of a single object file for the whole module, in a compilation action with
            the given flags.
        *   `emits_partial_modules`: `True` if the Swift frontend emits partial `.swiftmodule` files
            for the individual source files in a compilation action with the given flags.
    """
    saw_space_separated_num_threads = False
    num_threads = 1

    for copt in copts:
        if saw_space_separated_num_threads:
            saw_space_separated_num_threads = False
            num_threads = _safe_int(copt)
        elif copt == "-num-threads":
            saw_space_separated_num_threads = True
        elif copt.startswith("-num-threads="):
            num_threads = _safe_int(copt.split("=")[1])

    if not num_threads:
        fail("The value of '-num-threads' must be a positive integer.")

    return struct(
        emits_multiple_objects = not (is_wmo and num_threads == 1),
        emits_partial_modules = not is_wmo,
    )

def _exclude_swift_incompatible_define(define):
    """A `map_each` helper that excludes the given define if it is not Swift-compatible.

    This function rejects any defines that are not of the form `FOO=1` or `FOO`. Note that in
    C-family languages, the option `-DFOO` is equivalent to `-DFOO=1` so we must preserve both.

    Args:
        define: A string of the form `FOO` or `FOO=BAR` that represents an Objective-C define.

    Returns:
        The token portion of the define it is Swift-compatible, or `None` otherwise.
    """
    token, equal, value = define.partition("=")
    if (not equal and not value) or (equal == "=" and value == "1"):
        return token
    return None

def _safe_int(s):
    """Returns the integer value of `s` when interpreted as base 10, or `None` if it is invalid.

    This function is needed because `int()` fails the build when passed a string that isn't a valid
    integer, with no way to recover (https://github.com/bazelbuild/bazel/issues/5940).

    Args:
        s: The string to be converted to an integer.

    Returns:
        The integer value of `s`, or `None` if was not a valid base 10 integer.
    """
    for i in range(len(s)):
        if s[i] < "0" or s[i] > "9":
            return None
    return int(s)
