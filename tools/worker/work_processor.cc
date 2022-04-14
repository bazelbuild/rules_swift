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

#include "tools/worker/work_processor.h"

#include <sys/stat.h>

#include <fstream>
#include <sstream>
#include <string>

#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"
#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/temp_file.h"
#include "tools/worker/output_file_map.h"
#include "tools/worker/swift_runner.h"
#include "tools/worker/worker_protocol.h"

namespace {

// Returns true if the given command line argument enables whole-module
// optimization in the compiler.
static bool ArgumentEnablesWMO(absl::string_view arg) {
  return arg == "-wmo" || arg == "-whole-module-optimization" ||
         arg == "-force-single-frontend-invocation";
}

};  // end namespace

WorkProcessor::WorkProcessor(const std::vector<std::string> &args) {
  universal_args_.insert(universal_args_.end(), args.begin(), args.end());
}

void WorkProcessor::ProcessWorkRequest(
    const bazel_rules_swift::worker_protocol::WorkRequest &request,
    bazel_rules_swift::worker_protocol::WorkResponse &response) {
  std::vector<std::string> processed_args(universal_args_);

  // Bazel's worker spawning strategy reads the arguments from the params file
  // and inserts them into the proto. This means that if we just try to pass
  // them verbatim to swiftc, we might end up with a command line that's too
  // long. Rather than try to figure out these limits (which is very
  // OS-specific and easy to get wrong), we unconditionally write the processed
  // arguments out to a params file.
  std::unique_ptr<TempFile> params_file =
      TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream params_file_stream(std::string(params_file->GetPath()));

  OutputFileMap output_file_map;
  std::string output_file_map_path;
  bool is_wmo = false;

  std::string prev_arg;
  for (std::string arg : request.arguments) {
    std::string original_arg = arg;
    // Peel off the `-output-file-map` argument, so we can rewrite it if
    // necessary later.
    if (arg == "-output-file-map") {
      arg.clear();
    } else if (prev_arg == "-output-file-map") {
      output_file_map_path = arg;
      output_file_map.ReadFromPath(output_file_map_path);
      arg.clear();
    } else if (ArgumentEnablesWMO(arg)) {
      is_wmo = true;
    }

    if (!arg.empty()) {
      params_file_stream << arg << '\n';
    }

    prev_arg = original_arg;
  }

  if (!output_file_map_path.empty()) {
    if (!is_wmo) {
      // Rewrite the output file map to use the incremental storage area and
      // pass the compiler the path to the rewritten file.
      std::string new_path =
          ReplaceExtension(output_file_map_path, ".incremental.json");
      output_file_map.WriteToPath(new_path);

      params_file_stream << "-output-file-map\n";
      params_file_stream << new_path << '\n';

      // Pass the incremental flags only if WMO is disabled. WMO would overrule
      // incremental mode anyway, but since we control the passing of this flag,
      // there's no reason to pass it when it's a no-op.
      params_file_stream << "-incremental\n";
    } else {
      // If WMO is forcing us out of incremental mode, just put the original
      // output file map back so the outputs end up where they should.
      params_file_stream << "-output-file-map\n";
      params_file_stream << output_file_map_path << '\n';
    }
  }

  processed_args.push_back(absl::StrCat("@", params_file->GetPath()));
  params_file_stream.close();

  if (!is_wmo) {
    for (const auto &[unused, incremental_path] :
         output_file_map.incremental_outputs()) {
      // Bazel creates the intermediate directories for the files declared at
      // analysis time, but we need to manually create the ones for the
      // incremental storage area.
      absl::string_view dir_path = Dirname(incremental_path);
      if (!MakeDirs(dir_path, S_IRWXU)) {
        std::cerr << "Could not create directory " << dir_path << " (errno "
                  << errno << ")\n";
      }
    }
  }

  std::ostringstream stderr_stream;
  SwiftRunner swift_runner(processed_args, /*force_response_file=*/true);

  int exit_code = swift_runner.Run(stderr_stream, /*stdout_to_stderr=*/true);

  if (!is_wmo) {
    // Copy the output files from the incremental storage area back to the
    // locations where Bazel declared the files.
    for (const auto &[original_path, incremental_path] :
         output_file_map.incremental_outputs()) {
      if (!CopyFile(incremental_path, original_path)) {
        std::cerr << "Could not copy " << incremental_path << " to "
                  << original_path << " (errno " << errno << ")\n";
        exit_code = EXIT_FAILURE;
      }
    }
  }

  response.exit_code = exit_code;
  response.output = stderr_stream.str();
  response.request_id = request.request_id;
  response.was_cancelled = false;
}
