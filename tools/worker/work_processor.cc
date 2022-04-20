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

#include <google/protobuf/text_format.h>
#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"
#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/temp_file.h"
#include "tools/worker/output_file_map.h"
#include "tools/worker/swift_runner.h"
#include <nlohmann/json.hpp>

namespace bazel_rules_swift {

namespace {

// Returns true if the given command line argument enables whole-module
// optimization in the compiler.
bool ArgumentEnablesWMO(absl::string_view arg) {
  return arg == "-wmo" || arg == "-whole-module-optimization" ||
         arg == "-force-single-frontend-invocation";
}

// Creates the directory structure in the incremental storage area that is
// needed for the compiler to write its outputs before they are copied to the
// locations where Bazel expects the declared files.
absl::Status PrepareIncrementalStorageArea(
    const OutputFileMap &output_file_map) {
  for (const auto &[unused, incremental_path] :
       output_file_map.incremental_outputs()) {
    // Bazel creates the intermediate directories for the files declared at
    // analysis time, but we need to manually create the ones for the
    // incremental storage area.
    if (absl::Status status = MakeDirs(Dirname(incremental_path), S_IRWXU);
        !status.ok()) {
      return status;
    }
  }
  return absl::OkStatus();
}

}  // end namespace

WorkProcessor::WorkProcessor(const std::vector<std::string> &args) {
  universal_args_.insert(universal_args_.end(), args.begin(), args.end());
}

void WorkProcessor::ProcessWorkRequest(
    const blaze::worker::WorkRequest &request,
    blaze::worker::WorkResponse *response) {
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
  std::string swiftmodule_path;
  bool is_incremental = true;

  std::string prev_arg;
  for (std::string arg : request.arguments()) {
    std::string original_arg = arg;
    // Peel off the `-output-file-map` argument, so we can rewrite it if
    // necessary later.
    if (arg == "-output-file-map") {
      arg.clear();
    } else if (prev_arg == "-output-file-map") {
      output_file_map_path = arg;
      arg.clear();
    } else if (arg == "-emit-module-path") {
      // Peel off the `-emit-module-path` argument, so we can rewrite it if
      // necessary later.
      arg.clear();
    } else if (prev_arg == "-emit-module-path") {
      swiftmodule_path = arg;
      arg.clear();
    } else if (ArgumentEnablesWMO(arg)) {
      // WMO disables incremental mode.
      is_incremental = false;
    }

    if (!arg.empty()) {
      params_file_stream << arg << '\n';
    }

    prev_arg = original_arg;
  }

  // If we didn't find the output file map on the command line for some reason,
  // treat this as a non-incremental build. That file has information we require
  // to persist the incremental state.
  if (output_file_map_path.empty()) {
    is_incremental = false;
  }

  std::ostringstream stderr_stream;

  if (is_incremental) {
    output_file_map.ReadFromPath(output_file_map_path, swiftmodule_path);

    if (absl::Status status = PrepareIncrementalStorageArea(output_file_map);
        !status.ok()) {
      // If we failed to create the incremental storage area, log a warning
      // message but fall back to a non-incremental compile. Don't treat this as
      // a hard failure; that's a bit too severe since we can recover from it.
      is_incremental = false;
      stderr_stream
          << "warning: Could not prepare the incremental storage area; "
          << status.message() << std::endl;
      stderr_stream << "note: Falling back to full compile" << std::endl;
    } else {
      // Rewrite the output file map to use the incremental storage area and
      // pass the compiler the path to the rewritten file.
      std::string new_path = MakeIncrementalOutputPath(output_file_map_path);
      output_file_map.WriteToPath(new_path);

      params_file_stream << "-output-file-map\n";
      params_file_stream << new_path << '\n';

      // Pass the incremental flags only if WMO is disabled. WMO would overrule
      // incremental mode anyway, but since we control the passing of this flag,
      // there's no reason to pass it when it's a no-op.
      params_file_stream << "-incremental\n";
    }
  }

  if (!is_incremental) {
    // If WMO or a preparation failure is forcing us out of incremental mode,
    // just put the original output file map back so the outputs end up where
    // they should.
    params_file_stream << "-output-file-map\n";
    params_file_stream << output_file_map_path << '\n';
  }

  if (!swiftmodule_path.empty()) {
    params_file_stream << "-emit-module-path\n";
    if (is_incremental) {
      // If we're compiling incrementally, write the overall `.swiftmodule` file
      // to the incremental storage space; it will be copied to the output root
      // with the other incremental outputs.
      params_file_stream << MakeIncrementalOutputPath(swiftmodule_path) << '\n';
    } else {
      // If we're not compiling incrementally, just write the `.swiftmodule`
      // file directly to the output root.
      params_file_stream << swiftmodule_path << '\n';
    }
  }

  processed_args.push_back(absl::StrCat("@", params_file->GetPath()));
  params_file_stream.close();

  SwiftRunner swift_runner(processed_args, /*force_response_file=*/true);
  int exit_code = swift_runner.Run(stderr_stream, /*stdout_to_stderr=*/true);

  if (is_incremental) {
    // Copy the output files from the incremental storage area back to the
    // locations where Bazel declared the files.
    for (const auto &[original_path, incremental_path] :
         output_file_map.incremental_outputs()) {
      if (absl::Status status = CopyFile(incremental_path, original_path);
          !status.ok()) {
        // Log any errors trying to copy the files back to their proper
        // locations. These are hard failures.
        stderr_stream << "error: " << status.message() << std::endl;
        exit_code = EXIT_FAILURE;
      }
    }
  }

  response->set_exit_code(exit_code);
  response->set_output(stderr_stream.str());
  response->set_request_id(request.request_id());
}

}  // namespace bazel_rules_swift
