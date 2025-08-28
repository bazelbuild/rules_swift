// Copyright 2019 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_SWIFT_RUNNER_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_SWIFT_RUNNER_H_

#include <functional>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"
#include "absl/strings/string_view.h"
#include "tools/common/bazel_substitutions.h"
#include "tools/common/temp_file.h"

namespace bazel_rules_swift {

// Represents a single step in a parallelized compilation.
struct CompileStep {
  // The name of the action that emits this output.
  std::string action;

  // The path of the expected primary output file, which identifies the step
  // among all of the frontend actions in the driver's job list.
  std::string output;
};

// Handles spawning the Swift compiler driver, making any required substitutions
// of the command line arguments (for example, Bazel's magic Xcode placeholder
// strings).
//
// The first argument in the list passed to the spawner should be the Swift
// tool that should be invoked (for example, "swiftc"). This spawner also
// recognizes special arguments of the form `-Xwrapped-swift=<arg>`. Arguments
// of this form are consumed entirely by this wrapper and are not passed down to
// the Swift tool (however, they may add normal arguments that will be passed).
//
// The following spawner-specific arguments are supported:
//
// -Xwrapped-swift=-debug-prefix-pwd-is-dot
//     When specified, the Swift compiler will be directed to remap the current
//     directory's path to the string "." in debug info. This remapping must be
//     applied here because we do not know the current working directory at
//     analysis time when the argument list is constructed.
//
// -Xwrapped-swift=-file-prefix-pwd-is-dot
//     When specified, the Swift compiler will be directed to remap the current
//     directory's path to the string "." in debug, coverage, and index info.
//     This remapping must be applied here because we do not know the current
//     working directory at analysis time when the argument list is constructed.
//
// -Xwrapped-swift=-ephemeral-module-cache
//     When specified, the spawner will create a new temporary directory, pass
//     that to the Swift compiler using `-module-cache-path`, and then delete
//     the directory afterwards. This should resolve issues where the module
//     cache state is not refreshed correctly in all situations, which
//     sometimes results in hard-to-diagnose crashes in `swiftc`.
class SwiftRunner {
 public:
  // Create a new spawner that launches a Swift tool with the given arguments.
  // The first argument is assumed to be that tool. If force_response_file is
  // true, then the remaining arguments will be unconditionally written into a
  // response file instead of being passed on the command line.
  SwiftRunner(const std::vector<std::string> &args,
              bool force_response_file = false);

  // Run the Swift compiler, redirecting stdout and stderr to the specified
  // streams.
  int Run(std::ostream &stdout_stream, std::ostream &stderr_stream);

 private:
  // Processes an argument that looks like it might be a response file (i.e., it
  // begins with '@') and returns true if the argument(s) passed to the consumer
  // were different than "arg").
  //
  // If the argument is not actually a response file (i.e., it begins with '@'
  // but the file cannot be read), then it is passed directly to the consumer
  // and this method returns false. Otherwise, if the response file could be
  // read, this method's behavior depends on a few factors:
  //
  // - If the spawner is forcing response files, then the arguments in this
  //   response file are read and processed and sent directly to the consumer.
  //   In other words, they will be rewritten into that new response file
  //   directly, rather than being kept in their own separate response file.
  //   This is because there is no reason to maintain the original and multiple
  //   response files at this stage of processing. In this case, the function
  //   returns true.
  //
  // - If the spawner is not forcing response files, then the arguments in this
  //   response file are read and processed. If none of the arguments changed,
  //   then this function passes the original response file argument to the
  //   consumer and returns false. If some arguments did change, then they are
  //   written to a new response file, a response file argument pointing to that
  //   file is passed to the consumer, and the method returns true.
  bool ProcessPossibleResponseFile(
      absl::string_view arg, std::function<void(absl::string_view)> consumer);

  // Applies substitutions for a single argument and passes the new arguments
  // (or the original, if no substitution was needed) to the consumer. Returns
  // true if any substitutions were made (that is, if the arguments passed to
  // the consumer were anything different than "arg").
  //
  // This method has file system side effects, creating temporary files and
  // directories as needed for a particular substitution.
  bool ProcessArgument(absl::string_view arg,
                       std::function<void(absl::string_view)> consumer);

  // Applies substitutions to the given command line arguments and populates the
  // `tool_args_` and `args_` vectors.
  void ProcessArguments(const std::vector<std::string> &args);

  // Spawns the generated header rewriter to perform any desired transformations
  // on the Clang header emitted from a Swift compilation.
  int PerformGeneratedHeaderRewriting(std::ostream &stdout_stream,
                                      std::ostream &stderr_stream);

  // Performs a layering check for the compilation, comparing the modules that
  // were imported by Swift code being compiled to the list of dependencies
  // declared in the build graph.
  int PerformLayeringCheck(std::ostream &stdout_stream,
                           std::ostream &stderr_stream);

  // Performs a safe JSON AST dump of the current compilation, which attempts to
  // recover from known crash issues in the Swift 6.1 implementation of the
  // feature.
  int PerformJsonAstDump(std::ostream &stdout_stream,
                         std::ostream &stderr_stream);

  // Upgrade any of the requested warnings to errors and then print all of the
  // diagnostics to the given stream. Updates the exit code if necessary (to
  // turn a previously successful compilation into a failing one).
  void ProcessDiagnostics(absl::string_view stderr_output,
                          std::ostream &stderr_stream, int &exit_code) const;

  // A mapping of Bazel placeholder strings to the actual paths that should be
  // substituted for them. Supports Xcode resolution on Apple OSes.
  bazel_rules_swift::BazelPlaceholderSubstitutions
      bazel_placeholder_substitutions_;

  // The portion of the command line that indicates which tool should be
  // spawned; that is, the name/path of the binary, possibly preceded by `xcrun`
  // on Apple platforms. This part of the path should never be written into a
  // response file.
  std::vector<std::string> tool_args_;

  // The arguments, post-substitution, passed to the spawner. This does not
  // include the binary path, and may be written into a response file.
  std::vector<std::string> args_;

  // The environment that should be passed to the original job (but not to other
  // jobs spawned by the worker, such as the generated header rewriter or the
  // emit-imports job).
  absl::flat_hash_map<std::string, std::string> job_env_;

  // Temporary files (e.g., rewritten response files) that should be cleaned up
  // after the driver has terminated.
  std::vector<std::unique_ptr<TempFile>> temp_files_;

  // Temporary directories (e.g., ephemeral module cache) that should be cleaned
  // up after the driver has terminated.
  std::vector<std::unique_ptr<TempDirectory>> temp_directories_;

  // Arguments will be unconditionally written into a response file and passed
  // to the tool that way.
  bool force_response_file_;

  // The path to the generated header rewriter tool, if one is being used for
  // this compilation.
  std::string generated_header_rewriter_path_;

  // A map containing arguments that should be passed through to additional
  // tools that support them. Each key in the map represents the name of a
  // recognized tool.
  absl::flat_hash_map<std::string, std::vector<std::string>>
      passthrough_tool_args_;

  // The Bazel target label that spawned the worker request, which can be used
  // in custom diagnostic messages printed by the worker.
  std::string target_label_;

  // The path to a file generated by the build rules that contains the list of
  // module names that are direct dependencies of the code being compiled. This
  // is used by layering checks to determine the set of modules that the code is
  // actually allowed to import.
  std::string deps_modules_path_;

  // Tracks whether the last flag seen was `-module-name`.
  bool last_flag_was_module_name_;

  // Tracks whether the last flag seen was `-tools-directory`.
  bool last_flag_was_tools_directory_;

  // Tracks whether the last flag seen was `-target`.
  bool last_flag_was_target_;

  // Tracks whether the last flag seen was `-module-alias`.
  bool last_flag_was_module_alias_;

  // The name of the module currently being compiled.
  std::string module_name_;

  // The target triple of the current compilation.
  std::string target_triple_;

  // The path to either the `.swiftinterface` file to compile or to a
  // `.swiftmodule` directory in which the worker will infer the interface file
  // to compile.
  std::string module_or_interface_path_;

  // A set containing the diagnostic IDs that should be upgraded from warnings
  // to errors by the worker.
  absl::flat_hash_set<std::string> warnings_as_errors_;

  // The step in the compilation plan that is being requested by this specific
  // action. If this is present, then the action is being executed as part of a
  // parallelized compilation and we should invoke the driver to list all jobs,
  // then extract and run the single frontend invocation that generates that
  // that output.
  std::optional<CompileStep> compile_step_;

  // Whether the worker should emit a JSON AST dump of the compilation.
  bool emit_json_ast_;

  // The inverse mapping of module aliases passed to the compiler. The
  // `-module-alias` flag takes its argument of the form `source=alias`. For
  // layering checks, we need to reverse this because `-emit-imported-modules`
  // reflects the aliased name and we want to present the original module names
  // in the error messages.
  absl::flat_hash_map<std::string, std::string> alias_to_source_mapping_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_SWIFT_RUNNER_H_
