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

#include "tools/worker/compile_without_worker.h"

#include <fstream>
#include <string>
#include <vector>

#include "tools/common/file_system.h"
#include "tools/common/string_utils.h"
#include "tools/common/temp_file.h"
#include "tools/worker/swift_runner.h"

namespace {

static void ProcessPossibleResponseFile(
    const std::string &arg, std::function<void(const std::string &)> consumer) {
  auto path = arg.substr(1);
  std::ifstream original_file(path);
  // If we couldn't open it, maybe it's not a file; maybe it's just some other
  // argument that starts with "@". (Unlikely, but it's safer to check.)
  if (!original_file.good()) {
    consumer(arg);
    return;
  }

  std::string arg_from_file;
  while (std::getline(original_file, arg_from_file)) {
    // Arguments in response files might be quoted/escaped, so we need to
    // unescape them ourselves.
    consumer(Unescape(arg_from_file));
  }
}

static std::tuple<bool, std::vector<std::string>>
    ArgumentsIncludingParamsContent(const std::vector<std::string> &args) {
  std::vector<std::string> full_args;
  std::string prev_arg;
  std::string index_store_path;
  std::string global_index_store_path;
  bool process_args = false;

  auto consumer = [&](const std::string &arg) {
    if (arg == "-index-store-path") {
      // Peel off the `-index-store-path` argument, so we can rewrite it if
      // necessary later.
    } else if (prev_arg == "-index-store-path") {
      index_store_path = arg;
    } else if (arg == "-Xwrapped-swift=-global-index-store-path") {
      // Minimally we want to not pass this argument to the worker, since it
      // can't process it
      process_args = true;
    } else if (prev_arg == "-Xwrapped-swift=-global-index-store-path") {
      global_index_store_path = arg;
    } else {
      full_args.push_back(arg);
    }

    prev_arg = arg;
  };

  for (auto arg : args) {
    if (arg[0] == '@') {
      ProcessPossibleResponseFile(arg, consumer);
    } else {
      consumer(arg);
    }
  }

  if (!global_index_store_path.empty() && FileExists(global_index_store_path + "/rules_swift_global_index_enabled")) {
    full_args.push_back("-index-store-path");
    full_args.push_back(global_index_store_path);
  } else if (!index_store_path.empty()) {
    // Add back index store path
    full_args.push_back("-index-store-path");
    full_args.push_back(index_store_path);
  }

  return std::make_tuple(process_args, full_args);
}

}  // end namespace

int CompileWithoutWorker(const std::vector<std::string> &args) {
  std::vector<std::string> actual_args(args.begin() + 1, args.end());
  auto arguments = ArgumentsIncludingParamsContent(actual_args);

  bool process_args = std::get<0>(arguments);
  if (!process_args) {
    return SwiftRunner(args).Run(&std::cerr, /*stdout_to_stderr=*/false);
  }

  // We have to rewrite the arguments. This means that if we just try to pass
  // the new arguments verbatim to swiftc, we might end up with a command line
  // that's too long. Rather than try to figure out these limits (which is very
  // OS-specific and easy to get wrong), we unconditionally write the processed
  // arguments out to a params file.
  auto params_file = TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream params_file_stream(params_file->GetPath());

  // Write out all processed arguments
  for (auto arg : std::get<1>(arguments)) {
    params_file_stream << arg << '\n';
  }

  std::vector<std::string> new_args(args.begin(), args.begin() + 1);
  new_args.push_back("@" + params_file->GetPath());
  params_file_stream.close();

  return SwiftRunner(new_args).Run(&std::cerr, /*stdout_to_stderr=*/false);
}
