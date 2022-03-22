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

#include <google/protobuf/text_format.h>
#include <sys/stat.h>

#include <fstream>
#include <map>
#include <nlohmann/json.hpp>
#include <sstream>
#include <string>

#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/temp_file.h"
#include "tools/worker/output_file_map.h"
#include "tools/worker/swift_runner.h"

namespace {

static void FinalizeWorkRequest(const blaze::worker::WorkRequest &request,
                                blaze::worker::WorkResponse *response,
                                int exit_code,
                                const std::ostringstream &output) {
  response->set_exit_code(exit_code);
  response->set_output(output.str());
  response->set_request_id(request.request_id());
}

};  // end namespace

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
  auto params_file = TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream params_file_stream(params_file->GetPath());

  OutputFileMap output_file_map;
  std::string output_file_map_path;
  std::string emit_module_path;
  bool is_wmo = false;
  bool is_dump_ast = false;

  std::string prev_arg;
  for (auto arg : request.arguments()) {
    auto original_arg = arg;
    // Peel off the `-output-file-map` argument, so we can rewrite it if
    // necessary later.
    if (arg == "-output-file-map") {
      arg.clear();
    } else if (arg == "-dump-ast") {
      is_dump_ast = true;
    } else if (prev_arg == "-output-file-map") {
      output_file_map_path = arg;
      arg.clear();
    } else if (prev_arg == "-emit-module-path") {
      emit_module_path = arg;
    } else if (ArgumentEnablesWMO(arg)) {
      is_wmo = true;
    }

    if (!arg.empty()) {
      params_file_stream << arg << '\n';
    }

    prev_arg = original_arg;
  }

  bool is_incremental = !is_wmo && !is_dump_ast;

  if (!output_file_map_path.empty()) {
    if (is_incremental) {
      output_file_map.ReadFromPath(output_file_map_path, emit_module_path);

      // Rewrite the output file map to use the incremental storage area and
      // pass the compiler the path to the rewritten file.
      auto new_path =
          ReplaceExtension(output_file_map_path, ".incremental.json");
      output_file_map.WriteToPath(new_path);

      params_file_stream << "-output-file-map\n";
      params_file_stream << new_path << '\n';

      // Pass the incremental flags only if WMO is disabled. WMO would overrule
      // incremental mode anyway, but since we control the passing of this flag,
      // there's no reason to pass it when it's a no-op.
      params_file_stream << "-incremental\n";
    } else {
      // If WMO or -dump-ast is forcing us out of incremental mode, just put the
      // original output file map back so the outputs end up where they should.
      params_file_stream << "-output-file-map\n";
      params_file_stream << output_file_map_path << '\n';
    }
  }

  processed_args.push_back("@" + params_file->GetPath());
  params_file_stream.close();

  std::ostringstream stderr_stream;

  if (is_incremental) {
    for (const auto &expected_object_pair :
         output_file_map.incremental_outputs()) {
      // Bazel creates the intermediate directories for the files declared at
      // analysis time, but we need to manually create the ones for the
      // incremental storage area.
      auto dir_path = Dirname(expected_object_pair.second);
      if (!MakeDirs(dir_path, S_IRWXU)) {
        stderr_stream << "swift_worker: Could not create directory " << dir_path
                      << " (errno " << errno << ")\n";
        FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
        return;
      }
    }

    // Copy some input files from the incremental storage area to the locations
    // where Bazel will generate them.
    for (const auto &expected_object_pair :
         output_file_map.incremental_inputs()) {
      if (FileExists(expected_object_pair.second)) {
        if (!CopyFile(expected_object_pair.second,
                      expected_object_pair.first)) {
          stderr_stream << "swift_worker: Could not copy "
                        << expected_object_pair.second << " to "
                        << expected_object_pair.first << " (errno " << errno
                        << ")\n";
          FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
          return;
        }
      }
    }
  }

  SwiftRunner swift_runner(processed_args, /*force_response_file=*/true);
  int exit_code = swift_runner.Run(&stderr_stream, /*stdout_to_stderr=*/true);

  if (is_incremental) {
    // Copy the output files from the incremental storage area back to the
    // locations where Bazel declared the files.
    for (const auto &expected_object_pair :
         output_file_map.incremental_outputs()) {
      if (!CopyFile(expected_object_pair.second, expected_object_pair.first)) {
        stderr_stream << "swift_worker: Could not copy "
                      << expected_object_pair.second << " to "
                      << expected_object_pair.first << " (errno " << errno
                      << ")\n";
        FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
        return;
      }
    }

    // Copy the replaced input files back to the incremental storage for the
    // next run.
    for (const auto &expected_object_pair :
         output_file_map.incremental_inputs()) {
      if (FileExists(expected_object_pair.first)) {
        if (FileExists(expected_object_pair.second)) {
          // CopyFile fails if the file already exists
          RemoveFile(expected_object_pair.second);
        }
        if (!CopyFile(expected_object_pair.first,
                      expected_object_pair.second)) {
          stderr_stream << "swift_worker: Could not copy "
                        << expected_object_pair.first << " to "
                        << expected_object_pair.second << " (errno " << errno
                        << ")\n";
          FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
          return;
        }
      } else if (exit_code == 0) {
        stderr_stream << "Failed to copy " << expected_object_pair.first
                      << " for incremental builds, maybe it wasn't produced?\n";
        FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
        return;
      }
    }
  }

  FinalizeWorkRequest(request, response, exit_code, stderr_stream);
}
