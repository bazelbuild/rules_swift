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

#include <algorithm>
#include <fstream>

#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/process.h"
#include "tools/common/string_utils.h"
#include "tools/common/temp_file.h"

namespace {

#if __APPLE__
// Returns the requested environment variable in the current process's
// environment. Aborts if this variable is unset.
static std::string GetMandatoryEnvVar(const std::string &var_name) {
  char *env_value = getenv(var_name.c_str());
  if (env_value == nullptr) {
    std::cerr << "Error: " << var_name << " not set.\n";
    abort();
  }
  return env_value;
}
#endif

// Creates a temporary file and writes the given arguments to it, one per line.
static std::unique_ptr<TempFile> WriteResponseFile(
    const std::vector<std::string> &args) {
  auto response_file = TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream response_file_stream(response_file->GetPath());

  for (const auto &arg : args) {
    // When Clang/Swift write out a response file to communicate from driver to
    // frontend, they just quote every argument to be safe; we duplicate that
    // instead of trying to be "smarter" and only quoting when necessary.
    response_file_stream << '"';
    for (auto ch : arg) {
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

}  // namespace

SwiftRunner::SwiftRunner(const std::vector<std::string> &args,
                         bool force_response_file)
    : force_response_file_(force_response_file) {
#if __APPLE__
  // On Apple platforms, replace the magic Bazel placeholders with the path
  // in the corresponding environment variable.
  std::string developer_dir = GetMandatoryEnvVar("DEVELOPER_DIR");
  std::string sdk_root = GetMandatoryEnvVar("SDKROOT");

  bazel_placeholder_substitutions_ = {
      {"__BAZEL_XCODE_DEVELOPER_DIR__", developer_dir},
      {"__BAZEL_XCODE_SDKROOT__", sdk_root},
  };
#else
  // We don't have these placeholder strings on non-Apple platforms.
#endif
  args_ = ProcessArguments(args);
}

int SwiftRunner::Run(std::ostream *stderr_stream, bool stdout_to_stderr) {
  int exit_code = RunSubProcess(args_, stderr_stream, stdout_to_stderr);
  return exit_code;
}

bool SwiftRunner::ProcessPossibleResponseFile(
    const std::string &arg, std::function<void(const std::string &)> consumer) {
  auto path = arg.substr(1);
  std::ifstream original_file(path);
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

  // Otherwise, open the file, process the arguments, and rewrite it if any of
  // them have changed.
  bool changed = false;
  std::string arg_from_file;
  std::vector<std::string> new_args;

  while (std::getline(original_file, arg_from_file)) {
    changed |=
        ProcessArgument(arg_from_file, [&](const std::string &processed_arg) {
          new_args.push_back(processed_arg);
        });
  }

  // If we have to transform source file paths, do another pass on the arguments
  if (use_absolute_paths_) {
    std::transform(
        new_args.begin(), new_args.end(), new_args.begin(), MakePathAbsolute);
  }

  if (changed) {
    auto new_file = WriteResponseFile(new_args);
    consumer("@" + new_file->GetPath());
    temp_files_.push_back(std::move(new_file));
  } else {
    // If none of the arguments changed, just keep the original response file
    // argument.
    consumer(arg);
  }

  return changed;
}

bool SwiftRunner::ProcessArgument(
    const std::string &arg, std::function<void(const std::string &)> consumer) {
  bool changed = false;

  if (arg[0] == '@') {
    changed = ProcessPossibleResponseFile(arg, consumer);
  } else if (arg == "-Xwrapped-swift=-debug-prefix-pwd-is-dot") {
    // Get the actual current working directory (the workspace root), which we
    // didn't know at analysis time.
    consumer("-debug-prefix-map");
    consumer(GetCurrentDirectory() + "=.");
    changed = true;
  } else if (arg == "-Xwrapped-swift=-ephemeral-module-cache") {
    // Create a temporary directory to hold the module cache, which will be
    // deleted after compilation is finished.
    auto module_cache_dir = TempDirectory::Create("swift_module_cache.XXXXXX");
    consumer("-module-cache-path");
    consumer(module_cache_dir->GetPath());
    temp_directories_.push_back(std::move(module_cache_dir));
    changed = true;
  } else if (arg == "-Xwrapped-swift=-use-absolute-paths") {
    use_absolute_paths_ = true;
    changed = true;
  } else if (arg.find("-Xwrapped-swift=") == 0) {
    // TODO(allevato): Report that an unknown wrapper arg was found and give the
    // caller a way to exit gracefully.
    changed = true;
  } else {
    // Apply any other text substitutions needed in the argument (i.e., for
    // Apple toolchains).
    auto new_arg = arg;
    // Bazel doesn't quote arguments in multi-line params files, so we need to
    // ensure that our defensive quoting kicks in if an argument contains a
    // space, even if no other changes would have been made.
    changed = MakeSubstitutions(&new_arg, bazel_placeholder_substitutions_) ||
              new_arg.find_first_of(' ') != std::string::npos;
    consumer(new_arg);
  }

  return changed;
}

std::vector<std::string> SwiftRunner::ProcessArguments(
    const std::vector<std::string> &args) {
  std::vector<std::string> new_args;
  std::vector<std::string> response_file_args;

#if __APPLE__
  // On Apple platforms, inject `/usr/bin/xcrun` in front of our command
  // invocation.
  new_args.push_back("/usr/bin/xcrun");
#endif

  // The tool is assumed to be the first argument. Push it directly.
  auto it = args.begin();
  new_args.push_back(*it++);

  // If we're forcing response files, push the remaining processed args onto a
  // different vector that we write out below. If not, push them directly onto
  // the vector being returned.
  auto &args_destination = force_response_file_ ? response_file_args : new_args;
  while (it != args.end()) {
    ProcessArgument(
        *it, [&](const std::string &arg) { args_destination.push_back(arg); });
    ++it;
  }

  // If we have to transform source file paths, do another pass on the arguments
  if (use_absolute_paths_) {
    std::transform(args_destination.begin(), args_destination.end(),
                   args_destination.begin(), MakePathAbsolute);
  }

  if (force_response_file_) {
    // Write the processed args to the response file, and push the path to that
    // file (preceded by '@') onto the arg list being returned.
    auto new_file = WriteResponseFile(response_file_args);
    new_args.push_back("@" + new_file->GetPath());
    temp_files_.push_back(std::move(new_file));
  }

  return new_args;
}
