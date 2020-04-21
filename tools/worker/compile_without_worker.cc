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

#include "tools/common/path_utils.h"
#include "tools/common/string_utils.h"
#include "tools/common/temp_file.h"
#include "tools/worker/output_file_map.h"
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

static std::tuple<std::vector<std::string>, std::string>
    ArgumentsIncludingParamsContent(const std::vector<std::string> &args) {
  std::vector<std::string> full_args;
  std::string prev_arg;
  std::string output_file_map_path;
  bool use_absolute_paths = false;

  auto consumer = [&](const std::string &arg) {
    if (arg == "-output-file-map") {
      // Peel off the `-output-file-map` argument, so we can rewrite it if
      // necessary later.
    } else if (prev_arg == "-output-file-map") {
      output_file_map_path = arg;
    } else if (arg == "-Xwrapped-swift=-use-absolute-paths") {
      use_absolute_paths = true;
      full_args.push_back(arg);
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

  std::string process_output_file_map_path;
  if (use_absolute_paths) {
    process_output_file_map_path = output_file_map_path;
  }

  return std::make_tuple(full_args, process_output_file_map_path);
}

}  // end namespace

int CompileWithoutWorker(const std::vector<std::string> &args) {
  std::vector<std::string> actual_args(args.begin() + 1, args.end());
  auto arguments = ArgumentsIncludingParamsContent(actual_args);

  // output_file_map_path will be non-empty if we need to process it.
  std::string output_file_map_path = std::get<1>(arguments);
  if (output_file_map_path.empty()) {
    return SwiftRunner(args).Run(&std::cerr, /*stdout_to_stderr=*/false);
  }

  // We have to rewrite the arguments to include a rewritten object_file_map.
  // This means that if we just try to pass the new arguments verbatim to
  // swiftc, we might end up with a command line that's too long. Rather than
  // try to figure out these limits (which is very OS-specific and easy to get
  // wrong), we unconditionally write the processed arguments out to a params
  // file.
  auto params_file = TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream params_file_stream(params_file->GetPath());

  // Write out all non-output_file_map arguments
  for (auto arg : std::get<0>(arguments)) {
    params_file_stream << arg << '\n';
  }

  OutputFileMap output_file_map;
  output_file_map.ReadFromPath(output_file_map_path);
  output_file_map.UpdateForAbsolutePaths();

  // Rewrite the output file map.
  auto new_path = ReplaceExtension(output_file_map_path, ".processed.json");
  output_file_map.WriteToPath(new_path);

  // Pass the compiler the path to the rewritten file.
  params_file_stream << "-output-file-map\n";
  params_file_stream << new_path << '\n';

  std::vector<std::string> new_args(args.begin(), args.begin() + 1);
  new_args.push_back("@" + params_file->GetPath());
  params_file_stream.close();

  return SwiftRunner(new_args).Run(&std::cerr, /*stdout_to_stderr=*/false);
}
