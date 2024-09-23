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
#include <memory>
#include <optional>
#include <ostream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "absl/container/btree_set.h"
#include "absl/container/flat_hash_map.h"
#include "absl/container/flat_hash_set.h"
#include "absl/status/statusor.h"
#include "absl/strings/match.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_split.h"
#include "absl/strings/string_view.h"
#include "absl/strings/strip.h"
#include "tools/common/color.h"
#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/process.h"
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
  RE2 response_file_pattern("@\\S+\\s+#");
  for (absl::string_view command_line_view :
       absl::StrSplit(print_jobs_output, '\n')) {
    if (command_line_view.empty()) {
      continue;
    }

    // If the driver created a response file for the frontend invocation, it
    // writes those arguments to a temporary file and then prints the actual
    // arguments with a shell comment-like notation. We remove the response
    // file argument and the comment marker so to retrieve the actual arguments
    // as if they were expanded; we'll write them back out to a response file
    // later, and this avoids depending on temporary files written by the driver
    // that might not always be preserved after the process terminates.
    std::string command_line(command_line_view);
    RE2::Replace(&command_line, response_file_pattern, "");

    if (absl::StrContains(command_line, " -c ")) {
      int index = codegen_jobs_.size();
      codegen_jobs_.push_back(command_line);

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
      module_jobs_.push_back(command_line);
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

// Unescape and unquote an argument read from a line of a response file.
static std::string Unescape(absl::string_view arg) {
  std::string result;
  size_t length = arg.size();
  for (size_t i = 0; i < length; ++i) {
    char ch = arg[i];

    // If it's a backslash, consume it and append the character that follows.
    if (ch == '\\' && i + 1 < length) {
      ++i;
      result.push_back(arg[i]);
      continue;
    }

    // If it's a quote, process everything up to the matching quote, unescaping
    // backslashed characters as needed.
    if (ch == '"' || ch == '\'') {
      char quote = ch;
      ++i;
      while (i != length && arg[i] != quote) {
        if (arg[i] == '\\' && i + 1 < length) {
          ++i;
        }
        result.push_back(arg[i]);
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

  return result;
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

// Executes the module-wide jobs in a compilation plan.
int SpawnCompileModuleStep(
    const CompilationPlan &plan, CompileStep compile_step,
    const absl::flat_hash_map<std::string, std::string> *env,
    std::ostream &stdout_stream, std::ostream &stderr_stream) {
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
    stderr_stream << "internal error: could not find the frontend command "
                     "for action "
                  << compile_step.action << " for some requested output in "
                  << compile_step.output << "\n";
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
      stderr_stream << "error spawning subprocess: " << process.status()
                    << "\n";
      return 1;
    }
    processes.emplace_back(std::move(*process));
  }

  int any_failing_exit_code = 0;
  for (std::unique_ptr<AsyncProcess> &process : processes) {
    absl::StatusOr<AsyncProcess::Result> result = process->WaitForTermination();
    if (!result.ok()) {
      stderr_stream << "error spawning or waiting for subprocess: "
                    << result.status() << "\n";
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

  stderr_stream << "internal error: unrecognized plan step "
                << compile_step.action << " with output " << compile_step.output
                << "\n";
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
  } else if (trimmed_arg == "-module-name") {
    last_flag_was_module_name_ = true;
  } else if (trimmed_arg == "-tools-directory") {
    last_flag_was_tools_directory_ = true;
  } else if (absl::ConsumePrefix(&trimmed_arg, "-Xwrapped-swift=")) {
    if (trimmed_arg == "-debug-prefix-pwd-is-dot") {
      // Get the actual current working directory (the execution root), which
      // we didn't know at analysis time.
      consumer("-debug-prefix-map");
      consumer(absl::StrCat(GetCurrentDirectory(), "=."));
      return true;
    }

    if (trimmed_arg == "-file-prefix-pwd-is-dot") {
      // Get the actual current working directory (the execution root), which
      // we didn't know at analysis time.
      consumer("-file-prefix-map");
      consumer(absl::StrCat(GetCurrentDirectory(), "=."));
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

  // If we're forcing response files, push the remaining processed args onto a
  // different vector that we write out below. If not, push them directly onto
  // the vector being returned.
  while (it != args.end()) {
    ProcessArgument(
        *it, [&](absl::string_view arg) { args_.push_back(std::string(arg)); });
    ++it;
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
        << "dependencies of the target:" << std::endl
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
  // in square brackets, either at the end of the string or followed by a
  // semicolon (for wrapped diagnostics). Nothing guarantees this for the
  // wrapped case -- it is just observed convention -- but it is sufficient
  // while the compiler doesn't give us a more proper way to detect these.
  RE2 diagnostic_name_pattern("\\[([_A-Za-z][_A-Za-z0-9]*)\\](;|$)");

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
