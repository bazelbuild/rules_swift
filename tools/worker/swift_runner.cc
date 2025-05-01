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

#include "tools/worker/swift_runner.h"

#include <fcntl.h>

#include <cstddef>
#include <fstream>
#include <functional>
#include <iostream>
#include <memory>
#include <optional>
#include <ostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "absl/base/nullability.h"
#include "absl/container/btree_set.h"
#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/match.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_split.h"
#include "absl/strings/string_view.h"
#include "absl/strings/strip.h"
#include "absl/strings/substitute.h"
#include "tools/common/color.h"
#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/process.h"
#include "tools/common/target_triple.h"
#include "tools/common/temp_file.h"
#include "re2/re2.h"

namespace bazel_rules_swift {

namespace {

// Extracts frontend command lines from the driver output and groups them into
// buckets that can be run based on the incoming `-compile-step` flag.
class CompilationPlan {
 public:
  // Creates a new compilation plan by parsing the given driver output.
  CompilationPlan(absl::string_view print_jobs_output);

  // Returns the list of module jobs extracted from the plan. Each job is a
  // command line that should be invoked to emit some module-wide output.
  const std::vector<std::string> &ModuleJobs() const { return module_jobs_; }

  // Returns the codegen job that is associated with the given output file, or
  // `nullopt` if none was found. The job is a command line that should be
  // invoked to emit some codegen-related output.
  std::vector<std::string> CodegenJobsForOutputs(
      std::vector<absl::string_view> outputs) const;

 private:
  // The command lines of any frontend jobs that emit a module or other
  // module-wide outputs, executed when the compilation step is
  // `SwiftCompileModule`. These are executed in sequence.
  std::vector<std::string> module_jobs_;

  // The command lines of any frontend jobs that emit codegen output, like
  // object files. These are mapped to the output path by
  // `codegen_job_indices_by_output_`.
  std::vector<std::string> codegen_jobs_;

  // The indices into `codegen_jobs_` of the command lines of any frontend jobs
  // that emit codegen output for some given output path.
  absl::flat_hash_map<std::string, int> codegen_job_indices_by_output_;
};

CompilationPlan::CompilationPlan(absl::string_view print_jobs_output) {
  // Looks for the `-o` flags in the command line and captures the path to that
  // file. This captures both regular paths (group 2) and single-quoted paths
  // (group 1).
  RE2 output_pattern("\\s-o\\s+(?:'((?:\\'|[^'])*)'|(\\S+))");
  for (absl::string_view command_line :
       absl::StrSplit(print_jobs_output, '\n')) {
    if (command_line.empty()) {
      continue;
    }

    // If the driver created a response file for the frontend invocation, then
    // it prints the actual arguments with a shell comment-like notation. This
    // is good for job scanning because we don't have to read the response files
    // to find the invocations for various output files, but when we invoke it
    // we need to strip that off because we aren't spawning like a shell; it
    // would interpret the `#` and everything that follows as regular arguments.
    // If the comment marker isn't there, then this logic also works because
    // `first` will be the same as the original string.
    std::pair<absl::string_view, absl::string_view> possible_response_file =
        absl::StrSplit(command_line, absl::MaxSplits(" # ", 1));
    absl::string_view command_line_without_expansions =
        possible_response_file.first;

    if (absl::StrContains(command_line, " -c ")) {
      int index = codegen_jobs_.size();
      codegen_jobs_.push_back(std::string(command_line_without_expansions));

      // When threaded WMO is enabled, a single invocation might emit multiple
      // object files. Associate them with the same command line so that they
      // are deduplicated.
      std::string quoted_path, normal_path;
      absl::string_view anchor = command_line;
      while (RE2::FindAndConsume(&anchor, output_pattern, &quoted_path,
                                 &normal_path)) {
        codegen_job_indices_by_output_[!quoted_path.empty() ? quoted_path
                                                            : normal_path] =
            index;
      }
    } else {
      module_jobs_.push_back(std::string(command_line_without_expansions));
    }
  }
}

std::vector<std::string> CompilationPlan::CodegenJobsForOutputs(
    std::vector<absl::string_view> outputs) const {
  // Fast-path: If there is only one batch, there's no reason to iterate over
  // all of these. The build rules use an empty string to represent this case.
  if (outputs.empty()) {
    return codegen_jobs_;
  }

  absl::btree_set<int> indices;
  for (absl::string_view desired_output : outputs) {
    for (const auto &[output, index] : codegen_job_indices_by_output_) {
      // We need to do a suffix search here because the driver may have
      // realpath-ed the output argument, giving us something like
      // `<path to work area>/bazel-out/...` when we're just expecting
      // `bazel-out/...`.
      if (absl::EndsWith(output, desired_output)) {
        indices.insert(index);
        break;
      }
    }
  }

  std::vector<std::string> jobs;
  jobs.reserve(indices.size());
  for (int index : indices) {
    jobs.push_back(codegen_jobs_[index]);
  }
  return jobs;
}

// Creates a temporary file and writes the given arguments to it, one per line.
static std::unique_ptr<TempFile> WriteResponseFile(
    const std::vector<std::string> &args) {
  std::unique_ptr<TempFile> response_file =
      TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream response_file_stream(std::string(response_file->GetPath()));

  for (absl::string_view arg : args) {
    // When Clang/Swift write out a response file to communicate from driver to
    // frontend, they just quote every argument to be safe; we duplicate that
    // instead of trying to be "smarter" and only quoting when necessary.
    response_file_stream << '"';
    for (char ch : arg) {
      if (ch == '"' || ch == '\\') {
        response_file_stream << '\\';
      }
      response_file_stream << ch;
    }
    response_file_stream << "\"\n";
  }

  response_file_stream.close();
  return response_file;
}

// Creates a temporary file and writes the given command line string to it
// without any additional processing.
static std::unique_ptr<TempFile> WriteDirectResponseFile(
    absl::string_view args) {
  std::unique_ptr<TempFile> response_file =
      TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream response_file_stream(std::string(response_file->GetPath()));
  response_file_stream << args;
  response_file_stream.close();
  return response_file;
}

// Consumes and returns a single argument from the given command line (skipping
// any leading whitespace and also handling quoted/escaped arguments), advancing
// the view to the end of the argument in a similar fashion to
// `absl::ConsumePrefix()`.
static std::optional<std::string> ConsumeArg(
    absl::string_view *absl_nonnull line) {
  size_t whitespace_count = 0;
  size_t length = line->size();
  while (whitespace_count < length && (*line)[whitespace_count] == ' ') {
    whitespace_count++;
  }
  if (whitespace_count > 0) {
    line->remove_prefix(whitespace_count);
  }

  if (line->empty()) {
    return std::nullopt;
  }

  std::string result;
  length = line->size();
  size_t i = 0;
  for (i = 0; i < length; ++i) {
    char ch = (*line)[i];

    if (ch == ' ') {
      break;
    }

    // If it's a backslash, consume it and append the character that follows.
    if (ch == '\\' && i + 1 < length) {
      ++i;
      result.push_back((*line)[i]);
      continue;
    }

    // If it's a quote, process everything up to the matching quote, unescaping
    // backslashed characters as needed.
    if (ch == '"' || ch == '\'') {
      char quote = ch;
      ++i;
      while (i != length && (*line)[i] != quote) {
        if ((*line)[i] == '\\' && i + 1 < length) {
          ++i;
        }
        result.push_back((*line)[i]);
        ++i;
      }
      if (i == length) {
        break;
      }
      continue;
    }

    // It's a regular character.
    result.push_back(ch);
  }

  line->remove_prefix(i);
  return result;
}

// Unescape and unquote an argument read from a line of a response file.
static std::string Unescape(absl::string_view arg) {
  return ConsumeArg(&arg).value_or("");
}

// Reads the list of module names that are direct dependencies of the code being
// compiled.
absl::btree_set<std::string> ReadDepsModules(absl::string_view path) {
  absl::btree_set<std::string> deps_modules;
  std::ifstream deps_file_stream(std::string(path.data(), path.size()));
  std::string line;
  while (std::getline(deps_file_stream, line)) {
    deps_modules.insert(std::string(line));
  }
  return deps_modules;
}

#if __APPLE__
// Returns true if the given argument list starts with an invocation of `xcrun`.
bool StartsWithXcrun(const std::vector<std::string> &args) {
  return !args.empty() && Basename(args[0]) == "xcrun";
}
#endif

// Spawns an executable, constructing the command line by writing `args` to a
// response file and concatenating that after `tool_args` (which are passed
// outside the response file).
int SpawnJob(const std::vector<std::string> &tool_args,
             const std::vector<std::string> &args,
             const absl::flat_hash_map<std::string, std::string> *env,
             std::ostream &stdout_stream, std::ostream &stderr_stream) {
  std::unique_ptr<TempFile> response_file = WriteResponseFile(args);

  std::vector<std::string> spawn_args(tool_args);
  spawn_args.push_back(absl::StrCat("@", response_file->GetPath()));
  return RunSubProcess(spawn_args, env, stdout_stream, stderr_stream);
}

// Logs an internal error message that occurred during compilation planning and
// provides users with a workaround.
void LogCompilePlanError(std::ostream &stderr_stream,
                         absl::string_view message) {
  WithColor(stderr_stream, Color::kBoldRed) << "Internal planning error: ";
  WithColor(stderr_stream, Color::kBold) << message << std::endl;
  WithColor(stderr_stream, Color::kBold)
      << "You can work around this bug by adding `features = "
         "[\"-swift.compile_in_parallel\"] to the affected target until the "
         "bug is fixed."
      << std::endl;
}

// Executes the module-wide jobs in a compilation plan.
int SpawnCompileModuleStep(
    const CompilationPlan &plan, CompileStep compile_step,
    const absl::flat_hash_map<std::string, std::string> *env,
    std::ostream &stdout_stream, std::ostream &stderr_stream) {
  // If we're trying to execute a SwiftCompileModule step but there aren't any
  // module jobs, then there was a bug in the planning phase.
  if (plan.ModuleJobs().empty()) {
    LogCompilePlanError(stderr_stream,
                        "Attempting to execute a SwiftCompileModule step but "
                        "there are no module-wide jobs.");
    return 1;
  }

  // Run module jobs sequentially, in case later ones have dependencies on the
  // outputs of earlier ones.
  for (absl::string_view job : plan.ModuleJobs()) {
    std::pair<absl::string_view, absl::string_view> tool_and_args =
        absl::StrSplit(job, absl::MaxSplits(' ', 1));
    std::vector<std::string> step_args{std::string(tool_and_args.first)};

    // We can write the rest of the string out to a response file directly;
    // there is no need to split it into individual arguments (and in fact,
    // doing so would need to be quotation-aware, since the driver will quote
    // arguments that contain spaces).
    std::unique_ptr<TempFile> response_file =
        WriteDirectResponseFile(tool_and_args.second);
    step_args.push_back(absl::StrCat("@", response_file->GetPath()));
    int exit_code = RunSubProcess(step_args, env, stdout_stream, stderr_stream);
    if (exit_code != 0) {
      return exit_code;
    }
  }
  return 0;
}

// Executes the codegen jobs in a compilation plan.
int SpawnCompileCodegenStep(
    const CompilationPlan &plan, CompileStep compile_step,
    const absl::flat_hash_map<std::string, std::string> *env,
    std::ostream &stdout_stream, std::ostream &stderr_stream) {
  // Run codegen jobs in parallel, since they should be independent of each
  // other and they are slower so they benefit more from parallelism.
  std::vector<std::unique_ptr<AsyncProcess>> processes;
  std::vector<std::string> jobs = plan.CodegenJobsForOutputs(
      // Work around awkward legacy behavior in absl::StrSplit() that causes an
      // empty string to be split into a single empty string instead of an empty
      // array.
      compile_step.output.empty() ? std::vector<absl::string_view>()
                                  : absl::StrSplit(compile_step.output, ','));
  if (jobs.empty()) {
    LogCompilePlanError(
        stderr_stream,
        absl::Substitute("Could not find the frontend command for action $0 "
                         "for some requested output in $1.",
                         compile_step.action, compile_step.output));
    return 1;
  }
  for (absl::string_view job : jobs) {
    std::pair<absl::string_view, absl::string_view> tool_and_args =
        absl::StrSplit(job, absl::MaxSplits(' ', 1));
    std::vector<std::string> step_args{std::string(tool_and_args.first)};

    // We can write the rest of the string out to a response file directly;
    // there is no need to split it into individual arguments (and in fact,
    // doing so would need to be quotation-aware, since the driver will quote
    // arguments that contain spaces).
    std::unique_ptr<TempFile> response_file =
        WriteDirectResponseFile(absl::StrCat(tool_and_args.second));
    absl::StatusOr<std::unique_ptr<AsyncProcess>> process =
        AsyncProcess::Spawn(step_args, std::move(response_file), env);
    if (!process.ok()) {
      LogCompilePlanError(
          stderr_stream,
          absl::Substitute("Could not spawn subprocess: $0.",
                           process.status().ToString(
                               absl::StatusToStringMode::kWithEverything)));
      return 1;
    }
    processes.emplace_back(std::move(*process));
  }

  int any_failing_exit_code = 0;
  for (std::unique_ptr<AsyncProcess> &process : processes) {
    absl::StatusOr<AsyncProcess::Result> result = process->WaitForTermination();
    if (!result.ok()) {
      LogCompilePlanError(
          stderr_stream,
          absl::Substitute("Error waiting for subprocess: $0.",
                           result.status().ToString(
                               absl::StatusToStringMode::kWithEverything)));
      return 1;
    }
    stdout_stream << result->stdout;
    stderr_stream << result->stderr;
    if (result->exit_code != 0) {
      // Don't return early if the job failed; if we have multiple jobs in the
      // batch, we want the user to see possible diagnostics from all of them.
      any_failing_exit_code = result->exit_code;
    }
  }
  return any_failing_exit_code;
}

// Spawns a single step in a parallelized compilation by getting a list of
// frontend jobs that the driver would normally spawn and then running the one
// that emits the output file for the requested plan step.
int SpawnPlanStep(const std::vector<std::string> &tool_args,
                  const std::vector<std::string> &args,
                  const absl::flat_hash_map<std::string, std::string> *env,
                  CompileStep compile_step, std::ostream &stdout_stream,
                  std::ostream &stderr_stream) {
  // Add `-driver-print-jobs` to the command line, which will cause the driver
  // to print the command lines of the frontend jobs it would normally spawn and
  // then exit without running them.
  std::vector<std::string> print_jobs_args(args);
  print_jobs_args.push_back("-driver-print-jobs");
  // Ensure that the default TMPDIR is used by the driver for this job, not the
  // one used to write macro expansions (which may not be accessible when that
  // directory is not a declared output of the action in Bazel).
  absl::flat_hash_map<std::string, std::string> print_jobs_env(*env);
  print_jobs_env.erase("TMPDIR");
  std::ostringstream captured_stdout_stream;
  int exit_code = SpawnJob(tool_args, print_jobs_args, &print_jobs_env,
                           captured_stdout_stream, stderr_stream);
  if (exit_code != 0) {
    return exit_code;
  }

  CompilationPlan plan(captured_stdout_stream.str());
  if (compile_step.action == "SwiftCompileModule") {
    return SpawnCompileModuleStep(plan, compile_step, env, stdout_stream,
                                  stderr_stream);
  }
  if (compile_step.action == "SwiftCompileCodegen") {
    return SpawnCompileCodegenStep(plan, compile_step, env, stdout_stream,
                                   stderr_stream);
  }

  LogCompilePlanError(
      stderr_stream,
      absl::Substitute("Unrecognized plan step $0 with output $1.",
                       compile_step.action, compile_step.output));
  return 1;
}

// Returns a value indicating whether an argument on the Swift command line
// should be skipped because it is incompatible with the
// `-emit-imported-modules` flag used for layering checks. The given iterator is
// also advanced if necessary past any additional flags (e.g., a path following
// a flag).
bool SkipLayeringCheckIncompatibleArgs(std::vector<std::string>::iterator &it) {
  if (*it == "-emit-module" || *it == "-emit-module-interface" ||
      *it == "-emit-object" || *it == "-emit-objc-header" ||
      *it == "-emit-const-values" || *it == "-wmo" ||
      *it == "-whole-module-optimization") {
    // Skip just this argument.
    return true;
  }
  if (*it == "-o" || *it == "-output-file-map" || *it == "-emit-module-path" ||
      *it == "-emit-module-interface-path" || *it == "-emit-objc-header-path" ||
      *it == "-emit-clang-header-path" || *it == "-emit-const-values-path" ||
      *it == "-num-threads") {
    // This flag has a value after it that we also need to skip.
    ++it;
    return true;
  }

  // Don't skip the flag.
  return false;
}

// Modules that can be imported without an explicit dependency. Specifically,
// the standard library is always provided, along with other modules that are
// distributed as part of the standard library even though they are separate
// modules.
static const absl::flat_hash_set<absl::string_view>
    kModulesIgnorableForLayeringCheck = {
        "Builtin",      "Swift",        "SwiftOnoneSupport",
        "_Backtracing", "_Concurrency", "_StringProcessing",
};

// Returns true if the module can be ignored for the purposes of layering check
// (that is, it does not need to be in `deps` even if imported).
bool IsModuleIgnorableForLayeringCheck(absl::string_view module_name) {
  return kModulesIgnorableForLayeringCheck.contains(module_name);
}

// Infers the path to the `.swiftinterface` file inside a `.swiftmodule`
// directory based on the given target triple.
//
// This roughly mirrors the logic in the Swift frontend's
// `forEachTargetModuleBasename` function at
// https://github.com/swiftlang/swift/blob/d36b06747a54689a09ca6771b04798fc42b3e701/lib/Serialization/SerializedModuleLoader.cpp#L55.
std::optional<std::string> InferInterfacePath(
    absl::string_view module_path, absl::string_view target_triple_string) {
  std::optional<TargetTriple> parsed_triple =
      TargetTriple::Parse(target_triple_string);
  if (!parsed_triple.has_value()) {
    return std::nullopt;
  }

  // The target triple passed to us by the build rules has already been
  // normalized (e.g., `macos` instead of `macosx`), so we don't have to do as
  // much work here as the frontend normally would.
  TargetTriple normalized_triple = parsed_triple->WithoutOSVersion();

  // First, try the triple we were given.
  std::string attempt = absl::Substitute("$0/$1.swiftinterface", module_path,
                                         normalized_triple.TripleString());
  if (PathExists(attempt)) {
    return attempt;
  }

  // Next, if the target triple is `arm64`, we can also load an `arm64e`
  // interface, so try that.
  if (normalized_triple.Arch() == "arm64") {
    TargetTriple arm64e_triple = normalized_triple.WithArch("arm64e");
    attempt = absl::Substitute("$0/$1.swiftinterface", module_path,
                               arm64e_triple.TripleString());
    if (PathExists(attempt)) {
      return attempt;
    }
  }

  return std::nullopt;
}

// Extracts flags from the given `.swiftinterface` file and passes them to the
// given consumer.
void ExtractFlagsFromInterfaceFile(
    absl::string_view module_or_interface_path, absl::string_view target_triple,
    std::function<void(absl::string_view)> consumer) {
  std::string interface_path;
  if (absl::EndsWith(module_or_interface_path, ".swiftinterface")) {
    interface_path = std::string(module_or_interface_path);
  } else {
    std::optional<std::string> inferred_path =
        InferInterfacePath(module_or_interface_path, target_triple);
    if (!inferred_path.has_value()) {
      return;
    }
    interface_path = *inferred_path;
  }

  // Add the path to the interface file as a source file argument, then extract
  // the flags from it and add them as well.
  consumer(interface_path);

  std::ifstream interface_file{std::string(interface_path)};
  std::string line;
  while (std::getline(interface_file, line)) {
    absl::string_view line_view = line;
    if (absl::ConsumePrefix(&line_view, "// swift-module-flags: ")) {
      bool skip_next = false;
      while (std::optional<std::string> flag = ConsumeArg(&line_view)) {
        if (skip_next) {
          skip_next = false;
        } else if (*flag == "-target") {
          // We have to skip the target triple in the interface file because it
          // might be slightly different from the one the rest of our
          // dependencies were compiled with. For example, if we are targeting
          // `arm64-apple-macos`, that is the architecture that any Clang
          // module dependencies will have used. If the module uses
          // `arm64e-apple-macos` instead, then it will not be compatible with
          // those Clang modules.
          skip_next = true;
        } else {
          consumer(*flag);
        }
      }
      return;
    }
  }
}

}  // namespace

SwiftRunner::SwiftRunner(const std::vector<std::string> &args,
                         bool force_response_file)
    : job_env_(GetCurrentEnvironment()),
      force_response_file_(force_response_file),
      last_flag_was_module_name_(false),
      last_flag_was_tools_directory_(false) {
  ProcessArguments(args);
}

int SwiftRunner::Run(std::ostream &stdout_stream, std::ostream &stderr_stream) {
  int exit_code = 0;

  // Do the layering check before compilation. This gives a better error message
  // in the event a Swift module is being imported that depends on a Clang
  // module that isn't already in the transitive closure, because that will fail
  // to compile ("cannot load underlying module for '...'").
  //
  // Note that this also means we have to do the layering check for all
  // compilation actions (module and codegen). Otherwise, since they can be
  // scheduled in either order, doing it only in one could cause error messages
  // to differ if there are layering violations.
  if (!deps_modules_path_.empty()) {
    exit_code = PerformLayeringCheck(stdout_stream, stderr_stream);
    if (exit_code != 0) {
      return exit_code;
    }
  }

  bool should_rewrite_header = false;

  // Spawn the originally requested job with its full argument list. Capture
  // stderr in a string stream, which we post-process to upgrade warnings to
  // errors if requested.
  if (compile_step_.has_value()) {
    std::ostringstream captured_stderr_stream;
    exit_code = SpawnPlanStep(tool_args_, args_, &job_env_, *compile_step_,
                              stdout_stream, captured_stderr_stream);
    ProcessDiagnostics(captured_stderr_stream.str(), stderr_stream, exit_code);
    if (exit_code != 0) {
      return exit_code;
    }

    // Handle post-processing for specific kinds of actions.
    if (compile_step_->action == "SwiftCompileModule") {
      should_rewrite_header = true;
    }
  } else {
    std::ostringstream captured_stderr_stream;
    exit_code = SpawnJob(tool_args_, args_, &job_env_, stdout_stream,
                         captured_stderr_stream);
    ProcessDiagnostics(captured_stderr_stream.str(), stderr_stream, exit_code);
    if (exit_code != 0) {
      return exit_code;
    }
    should_rewrite_header = true;
  }

  if (should_rewrite_header && !generated_header_rewriter_path_.empty()) {
    exit_code = PerformGeneratedHeaderRewriting(stdout_stream, stderr_stream);
    if (exit_code != 0) {
      return exit_code;
    }
  }

  return exit_code;
}

bool SwiftRunner::ProcessPossibleResponseFile(
    absl::string_view arg, std::function<void(absl::string_view)> consumer) {
  absl::string_view path = arg.substr(1);
  std::ifstream original_file((std::string(path)));
  // If we couldn't open it, maybe it's not a file; maybe it's just some other
  // argument that starts with "@". (Unlikely, but it's safer to check.)
  if (!original_file.good()) {
    consumer(arg);
    return false;
  }

  // If we're forcing response files, process and send the arguments from this
  // file directly to the consumer; they'll all get written to the same response
  // file at the end of processing all the arguments.
  if (force_response_file_) {
    std::string arg_from_file;
    while (std::getline(original_file, arg_from_file)) {
      // Arguments in response files might be quoted/escaped, so we need to
      // unescape them ourselves.
      ProcessArgument(Unescape(arg_from_file), consumer);
    }
    return true;
  }

  // Otherwise, open the file and process the arguments.
  bool changed = false;
  std::string arg_from_file;

  while (std::getline(original_file, arg_from_file)) {
    changed |= ProcessArgument(arg_from_file, consumer);
  }

  return changed;
}

bool SwiftRunner::ProcessArgument(
    absl::string_view arg, std::function<void(absl::string_view)> consumer) {
  if (arg[0] == '@') {
    return ProcessPossibleResponseFile(arg, consumer);
  }

  // Helper function for adding path remapping flags that depend on information
  // only known at execution time.
  auto add_prefix_map_flags = [&](absl::string_view flag) {
    // Get the actual current working directory (the execution root), which
    // we didn't know at analysis time.
    consumer(flag);
    consumer(absl::StrCat(GetCurrentDirectory(), "=."));

#if __APPLE__
    std::string developer_dir = "__BAZEL_XCODE_DEVELOPER_DIR__";
    if (bazel_placeholder_substitutions_.Apply(developer_dir)) {
      consumer(flag);
      consumer(absl::StrCat(developer_dir, "=/DEVELOPER_DIR"));
    }
#endif
  };

  absl::string_view trimmed_arg = arg;
  if (last_flag_was_module_name_) {
    module_name_ = std::string(trimmed_arg);
    last_flag_was_module_name_ = false;
  } else if (last_flag_was_tools_directory_) {
    // Make the value of `-tools-directory` absolute, otherwise swift-driver
    // will ignore it.
    std::string tools_directory = std::string(trimmed_arg);
    consumer(absl::StrCat(GetCurrentDirectory(), "/", tools_directory));
    last_flag_was_tools_directory_ = false;
    return true;
  } else if (last_flag_was_target_) {
    target_triple_ = std::string(trimmed_arg);
    last_flag_was_target_ = false;
  } else if (trimmed_arg == "-module-name") {
    last_flag_was_module_name_ = true;
  } else if (trimmed_arg == "-tools-directory") {
    last_flag_was_tools_directory_ = true;
  } else if (trimmed_arg == "-target") {
    last_flag_was_target_ = true;
  } else if (absl::ConsumePrefix(&trimmed_arg, "-Xwrapped-swift=")) {
    if (trimmed_arg == "-debug-prefix-pwd-is-dot") {
      add_prefix_map_flags("-debug-prefix-map");
      return true;
    }

    if (trimmed_arg == "-file-prefix-pwd-is-dot") {
      add_prefix_map_flags("-file-prefix-map");
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-macro-expansion-dir=")) {
      std::string temp_dir = std::string(trimmed_arg);

      // We don't have a clean way to report an error out of this function. If
      // If creating the directory fails, then the compiler will fail later
      // anyway.
      MakeDirs(temp_dir, S_IRWXU).IgnoreError();

      // By default, the compiler creates a directory under the system temp
      // directory to hold macro expansions. The underlying LLVM API lets us
      // customize this location by setting `TMPDIR` in the environment, so this
      // lets us redirect those files to a deterministic location. A pull
      // request like https://github.com/apple/swift/pull/67184 would let us do
      // the same thing without this trick, but it hasn't been merged.
      //
      // For now, this is the only major use of `TMPDIR` by the compiler, so we
      // can do this without other stuff that we don't want moving there. We may
      // need to revisit this logic if that changes.
      job_env_["TMPDIR"] = absl::StrCat(GetCurrentDirectory(), "/", temp_dir);
      return true;
    }

    if (trimmed_arg == "-ephemeral-module-cache") {
      // Create a temporary directory to hold the module cache, which will be
      // deleted after compilation is finished.
      std::unique_ptr<TempDirectory> module_cache_dir =
          TempDirectory::Create("swift_module_cache.XXXXXX");
      consumer("-module-cache-path");
      consumer(module_cache_dir->GetPath());
      temp_directories_.push_back(std::move(module_cache_dir));
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-generated-header-rewriter=")) {
      generated_header_rewriter_path_ = std::string(trimmed_arg);
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-tool-arg=")) {
      std::pair<std::string, std::string> arg_and_value =
          absl::StrSplit(trimmed_arg, absl::MaxSplits('=', 1));
      passthrough_tool_args_[arg_and_value.first].push_back(
          std::string(arg_and_value.second));
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-bazel-target-label=")) {
      target_label_ = std::string(trimmed_arg);
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-layering-check-deps-modules=")) {
      deps_modules_path_ = std::string(trimmed_arg);
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-warning-as-error=")) {
      warnings_as_errors_.insert(std::string(trimmed_arg));
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg, "-compile-step=")) {
      std::pair<std::string, std::string> action_and_output =
          absl::StrSplit(trimmed_arg, absl::MaxSplits('=', 1));
      compile_step_ =
          CompileStep{action_and_output.first, action_and_output.second};
      return true;
    }

    if (absl::ConsumePrefix(&trimmed_arg,
                            "-explicit-compile-module-from-interface=")) {
      module_or_interface_path_ = std::string(trimmed_arg);
      bazel_placeholder_substitutions_.Apply(module_or_interface_path_);
      return true;
    }

    // TODO(allevato): Report that an unknown wrapper arg was found and give
    // the caller a way to exit gracefully.
    return true;
  }

  // Apply any other text substitutions needed in the argument (i.e., for
  // Apple toolchains).
  //
  // Bazel doesn't quote arguments in multi-line params files, so we need to
  // ensure that our defensive quoting kicks in if an argument contains a
  // space, even if no other changes would have been made.
  std::string new_arg(arg);
  bool changed = bazel_placeholder_substitutions_.Apply(new_arg) ||
                 absl::StrContains(new_arg, ' ');
  consumer(new_arg);
  return changed;
}

void SwiftRunner::ProcessArguments(const std::vector<std::string> &args) {
#if __APPLE__
  // On Apple platforms, inject `/usr/bin/xcrun` in front of our command
  // invocation.
  tool_args_.push_back("/usr/bin/xcrun");
#endif

  // The tool is assumed to be the first argument. Push it directly.
  auto it = args.begin();
  tool_args_.push_back(*it++);

  auto consumer = [&](absl::string_view arg) {
    args_.push_back(std::string(arg));
  };
  while (it != args.end()) {
    ProcessArgument(*it, consumer);
    ++it;
  }

  // If we're doing an explicit interface build, we need to extract the flags
  // from the .swiftinterface file as well.
  if (!module_or_interface_path_.empty()) {
    ExtractFlagsFromInterfaceFile(module_or_interface_path_, target_triple_,
                                  consumer);
  }
}

int SwiftRunner::PerformGeneratedHeaderRewriting(std::ostream &stdout_stream,
                                                 std::ostream &stderr_stream) {
#if __APPLE__
  // Skip the `xcrun` argument that's added when running on Apple platforms,
  // since the header rewriter doesn't need it.
  int tool_binary_index = StartsWithXcrun(tool_args_) ? 1 : 0;
#else
  int tool_binary_index = 0;
#endif

  std::vector<std::string> rewriter_tool_args;
  rewriter_tool_args.push_back(generated_header_rewriter_path_);
  const std::vector<std::string> &passthrough_args =
      passthrough_tool_args_["generated_header_rewriter"];
  rewriter_tool_args.insert(rewriter_tool_args.end(), passthrough_args.begin(),
                            passthrough_args.end());
  rewriter_tool_args.push_back("--");
  rewriter_tool_args.push_back(tool_args_[tool_binary_index]);

  return SpawnJob(rewriter_tool_args, args_, /*env=*/nullptr, stdout_stream,
                  stderr_stream);
}

int SwiftRunner::PerformLayeringCheck(std::ostream &stdout_stream,
                                      std::ostream &stderr_stream) {
  // Run the compiler again, this time using `-emit-imported-modules` to
  // override whatever other behavior was requested and get the list of imported
  // modules.
  std::string imported_modules_path =
      ReplaceExtension(deps_modules_path_, ".imported-modules",
                       /*all_extensions=*/true);

  std::vector<std::string> emit_imports_args;
  for (auto it = args_.begin(); it != args_.end(); ++it) {
    if (!SkipLayeringCheckIncompatibleArgs(it)) {
      emit_imports_args.push_back(*it);
    }
  }

  emit_imports_args.push_back("-emit-imported-modules");
  emit_imports_args.push_back("-o");
  emit_imports_args.push_back(imported_modules_path);
  int exit_code = SpawnJob(tool_args_, emit_imports_args, /*env=*/nullptr,
                           stdout_stream, stderr_stream);
  if (exit_code != 0) {
    return exit_code;
  }

  absl::btree_set<std::string> deps_modules =
      ReadDepsModules(deps_modules_path_);

  // We have to insert the name of the module being compiled, as well. In most
  // cases, it's nonsensical for a module to import itself (Swift only flags
  // this as a warning), but it's specifically allowed when writing a Swift
  // overlay: when compiling Swift module X, `@_exported import X` specifically
  // imports the underlying Clang module for X.
  deps_modules.insert(module_name_);

  // Use a `btree_set` so that the output is automatically sorted
  // lexicographically.
  absl::btree_set<std::string> missing_deps;
  std::ifstream imported_modules_stream(imported_modules_path);
  std::string module_name;
  while (std::getline(imported_modules_stream, module_name)) {
    if (!IsModuleIgnorableForLayeringCheck(module_name) &&
        !deps_modules.contains(module_name)) {
      missing_deps.insert(module_name);
    }
  }

  if (!missing_deps.empty()) {
    stderr_stream << std::endl;
    WithColor(stderr_stream, Color::kBoldRed) << "error: ";
    WithColor(stderr_stream, Color::kBold) << "Layering violation in ";
    WithColor(stderr_stream, Color::kBoldGreen) << target_label_ << std::endl;
    stderr_stream
        << "The following modules were imported, but they are not direct "
        << "dependencies of the target or they are misspelled:" << std::endl
        << std::endl;

    for (const std::string &module_name : missing_deps) {
      stderr_stream << "    " << module_name << std::endl;
    }
    stderr_stream << std::endl;

    WithColor(stderr_stream, Color::kBold)
        << "Please add the correct 'deps' to " << target_label_
        << " to import those modules." << std::endl;
    return 1;
  }

  return 0;
}

void SwiftRunner::ProcessDiagnostics(absl::string_view stderr_output,
                                     std::ostream &stderr_stream,
                                     int &exit_code) const {
  if (stderr_output.empty()) {
    // Nothing to do if there was no output.
    return;
  }

  // Match the "warning: " prefix on a message, also capturing the preceding
  // ANSI color sequence if present.
  RE2 warning_pattern("((\\x1b\\[(?:\\d+)(?:;\\d+)*m)?warning:\\s)");
  // When `-debug-diagnostic-names` is enabled, names are printed as identifiers
  // in square brackets, either at the end of the string (modulo another escape
  // sequence like 'reset'), or when followed by a semicolon (for wrapped
  // diagnostics). Nothing guarantees this for the wrapped case -- it is just
  // observed convention -- but it is sufficient while the compiler doesn't give
  // us a more proper way to detect these.
  RE2 diagnostic_name_pattern("\\[([_A-Za-z][_A-Za-z0-9]*)\\](;|$|\\x1b)");

  for (absl::string_view line : absl::StrSplit(stderr_output, '\n')) {
    std::unique_ptr<std::string> modified_line;

    absl::string_view warning_label;
    std::optional<absl::string_view> ansi_sequence;
    if (RE2::PartialMatch(line, warning_pattern, &warning_label,
                          &ansi_sequence)) {
      absl::string_view diagnostic_name;
      absl::string_view line_cursor = line;

      // Search the diagnostic line for all possible diagnostic names surrounded
      // by square brackets.
      while (RE2::FindAndConsume(&line_cursor, diagnostic_name_pattern,
                                 &diagnostic_name)) {
        if (warnings_as_errors_.contains(diagnostic_name)) {
          modified_line = std::make_unique<std::string>(line);
          std::ostringstream error_label;
          if (ansi_sequence.has_value()) {
            error_label << Color(Color::kBoldRed);
          }
          error_label << "error (upgraded from warning): ";
          modified_line->replace(warning_label.data() - line.data(),
                                 warning_label.length(), error_label.str());
          if (exit_code == 0) {
            exit_code = 1;
          }

          // In the event that there are multiple diagnostics on the same line
          // (this is the case, for example, with "this is an error in Swift 6"
          // messages), we can stop after we find the first match; the whole
          // line will become an error.
          break;
        }
      }
    }
    if (modified_line) {
      stderr_stream << *modified_line << std::endl;
    } else {
      stderr_stream << line << std::endl;
    }
  }
}

}  // namespace bazel_rules_swift
