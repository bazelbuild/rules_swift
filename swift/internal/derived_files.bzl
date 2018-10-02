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

"""Factory functions for declaring derived files and directories."""

load(":utils.bzl", "owner_relative_path")
load("@bazel_skylib//lib:paths.bzl", "paths")

def _ar_mri_script(actions, for_archive):
    """Declares a file for the MRI script that will be used to create an archive.

    Args:
      actions: The context's actions object.
      for_archive: A `File` representing the static archive that will be created.

    Returns:
      The declared `File`.
    """
    return actions.declare_file(
        "{}.mri".format(for_archive.basename),
        sibling = for_archive,
    )

def _ar_safe_object_path(path):
    """Return the path for a new .o file that is safe for a GNU `ar` MRI script.

    GNU `ar` uses an extremely primitive lex/yacc-based parser for MRI scripts
    that only supports the following characters in file paths: A-Z, a-z, 0-9,
    slash (/), backslash (\), dollar sign ($), colon (:), period (.), hyphen (-),
    and underscore (_). Notably, it does *not* support the plus sign (+), which is
    quite commonly used in Swift to denote files that contain extensions. This
    file returns an MRI-safe .o file name for a particular source file by applying
    the following mapping:

      * _  ->  __
      * +  ->  _P
      * All other characters stay the same.

    This is a helper function and is not exported in the `derived_files` module.

    Args:
      path: The path of the file being created.

    Returns:
      A safe version of the file path.
    """
    safe_path = ""
    for i in range(0, len(path)):
        ch = path[i]
        if ch == "_":
            safe_path += "__"
        elif ch == "+":
            safe_path += "_P"
        else:
            safe_path += ch
    return safe_path

def _autolink_flags(actions, target_name):
    """Declares the response file into which autolink flags will be extracted.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}.autolink".format(target_name))

def _executable(actions, target_name):
    """Declares a file for the executable created by a binary or test rule.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file(target_name)

def _indexstore_directory(actions, target_name):
    """Declares a directory in which the compiler's indexstore will be written.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_directory("{}.indexstore".format(target_name))

def _intermediate_frontend_file_path(target_name, src):
    """Returns the path to the directory for intermediate compile outputs.

    This is a helper function and is not exported in the `derived_files` module.

    Args:
      target_name: The name of hte target being built.
      src: A `File` representing the source file whose intermediate frontend
          artifacts path should be returned.

    Returns:
      The path to the directory where intermediate artifacts for the given target
      and source file should be stored.
    """
    objs_dir = "{}_objs".format(target_name)
    owner_rel_path = owner_relative_path(src)
    return paths.join(objs_dir, paths.dirname(owner_rel_path)), src.basename

def _intermediate_object_file(actions, target_name, src):
    """Declares a file for an intermediate object file during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled); in that case, there is
    a `.o` file produced for each source file, rather than a single `.o` for the
    entire module.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.
      src: A `File` representing the source file being compiled.

    Returns:
      The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(
        paths.join(dirname, _ar_safe_object_path("{}.o".format(basename))),
    )

def _module_map(actions, target_name):
    """Declares the module map for the generated Objective-C header of a target.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file(
        "{}.modulemaps/module.modulemap".format(target_name),
    )

def _modulewrap_object(actions, target_name):
    """Declares the object file used to wrap Swift modules for ELF binaries.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}.modulewrap.o".format(target_name))

def _objc_header(actions, target_name):
    """Declares the generated header file exposing Swift APIs to Objective-C.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}-Swift.h".format(target_name))

def _partial_swiftmodule(actions, target_name, src):
    """Declares a file for a partial Swift module created during compilation.

    These files are produced when the compiler is invoked with multiple frontend
    invocations (i.e., whole module optimization disabled); in that case, there is
    a partial `.swiftmodule` file produced for each source file, which are then
    merged by another frontend invocation to produce the single `.swiftmodule`
    file for the entire module.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.
      src: A `File` representing the source file being compiled.

    Returns:
      The declared `File`.
    """
    dirname, basename = _intermediate_frontend_file_path(target_name, src)
    return actions.declare_file(
        paths.join(dirname, "{}.partial_swiftmodule".format(basename)),
    )

def _reexport_modules_src(actions, target_name):
    """Declares a source file used to re-export other Swift modules.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}_exports.swift".format(target_name))

def _static_archive(actions, alwayslink, link_name):
    """Declares a file for the static archive created by a compilation rule.

    Args:
      actions: The context's actions object.
      alwayslink: Whether to always link all object files from the archive,
          even if they aren't referenced.
      link_name: The name of the library being built, without a `lib` prefix or
          file extension.

    Returns:
      The declared `File`.
    """
    extension = "lo" if alwayslink else "a"
    return actions.declare_file("lib{}.{}".format(link_name, extension))

def _swiftc_output_file_map(actions, target_name):
    """Declares a file for the JSON-formatted output map for a compilation action.

    This output map file allows us to supply our own paths and filenames for the
    intermediate artifacts produced by multiple frontend invocation, rather than
    using the temporary defaults

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}.output_file_map.json".format(target_name))

def _swiftdoc(actions, module_name):
    """Declares a file for the Swift doc file created by a compilation rule.

    Args:
      actions: The context's actions object.
      module_name: The name of the module being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}.swiftdoc".format(module_name))

def _swiftmodule(actions, module_name):
    """Declares a file for the Swift module created by a compilation rule.

    Args:
      actions: The context's actions object.
      module_name: The name of the module being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file("{}.swiftmodule".format(module_name))

def _whole_module_object_file(actions, target_name):
    """Declares a file for the object file created with whole module optimization.

    This is the output of a compile action when whole module optimization is
    enabled, which means that the driver produces a single frontend invocation
    that compiles all the source files at once.

    Args:
      actions: The context's actions object.
      target_name: The name of the target being built.

    Returns:
      The declared `File`.
    """
    return actions.declare_file(_ar_safe_object_path("{}.o".format(target_name)))

def _xctest_bundle(actions, target_name):
    """Declares a directory representing the `.xctest` bundle of a Darwin `swift_test`.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return actions.declare_directory("{}.xctest".format(target_name))

def _xctest_runner_script(actions, target_name):
    """Declares a file for the script that runs an `.xctest` bundle on Darwin.

    Args:
        actions: The context's actions object.
        target_name: The name of the target being built.

    Returns:
        The declared `File`.
    """
    return actions.declare_file("{}.test-runner.sh".format(target_name))

derived_files = struct(
    ar_mri_script = _ar_mri_script,
    autolink_flags = _autolink_flags,
    executable = _executable,
    indexstore_directory = _indexstore_directory,
    intermediate_object_file = _intermediate_object_file,
    module_map = _module_map,
    modulewrap_object = _modulewrap_object,
    objc_header = _objc_header,
    partial_swiftmodule = _partial_swiftmodule,
    reexport_modules_src = _reexport_modules_src,
    static_archive = _static_archive,
    swiftc_output_file_map = _swiftc_output_file_map,
    swiftdoc = _swiftdoc,
    swiftmodule = _swiftmodule,
    whole_module_object_file = _whole_module_object_file,
    xctest_bundle = _xctest_bundle,
    xctest_runner_script = _xctest_runner_script,
)
