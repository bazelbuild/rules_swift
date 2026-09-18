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

#if defined(__APPLE__)
#include <copyfile.h>
#endif
#include <sys/stat.h>

#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>

#include "tools/common/file_system.h"
#include "tools/common/temp_file.h"
#include "tools/worker/output_file_map.h"
#include "tools/worker/swift_runner.h"
#include "tools/worker/worker_protocol.h"

namespace {

using bazel_rules_swift::LongPath;

bool copy_file(const std::filesystem::path& from,
               const std::filesystem::path& to, std::error_code& ec) noexcept {
#if defined(__APPLE__)
  if (copyfile(from.string().c_str(), to.string().c_str(), nullptr,
               COPYFILE_ALL | COPYFILE_CLONE) < 0) {
    ec = std::error_code(errno, std::system_category());
    return false;
  }
  ec = std::error_code();
  return true;
#else
  return std::filesystem::copy_file(
      LongPath(from), LongPath(to),
      std::filesystem::copy_options::overwrite_existing, ec);
#endif
}

static void FinalizeWorkRequest(
    const bazel_rules_swift::worker_protocol::WorkRequest& request,
    bazel_rules_swift::worker_protocol::WorkResponse& response, int exit_code,
    const std::ostringstream& output) {
  response.exit_code = exit_code;
  response.output = output.str();
  response.request_id = request.request_id;
  response.was_cancelled = false;
}

};  // end namespace

WorkProcessor::WorkProcessor(const std::vector<std::string>& args,
                             std::string index_import_path)
    : index_import_path_(index_import_path) {
  universal_args_.insert(universal_args_.end(), args.begin(), args.end());
}

void WorkProcessor::ProcessWorkRequest(
    const bazel_rules_swift::worker_protocol::WorkRequest& request,
    bazel_rules_swift::worker_protocol::WorkResponse& response) {
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
  std::map<std::string, std::string> module_outputs;
  const std::set<std::string> module_output_flags = {
      "-emit-module-path",
      "-emit-module-source-info-path",
      "-emit-module-interface-path",
      "-emit-private-module-interface-path",
      "-emit-package-module-interface-path",
      "-emit-objc-header-path",
  };
  bool is_wmo = false;
  bool is_dump_ast = false;
  bool avoid_source_info = false;

  std::string prev_arg;
  for (const auto& arg : request.arguments) {
    if (prev_arg == "-output-file-map") {
      output_file_map_path = arg;
    } else if (module_output_flags.count(prev_arg)) {
      module_outputs[prev_arg] = arg;
    } else if (arg == "-dump-ast") {
      is_dump_ast = true;
    } else if (arg == "-avoid-emit-module-source-info") {
      avoid_source_info = true;
    } else if (ArgumentEnablesWMO(arg)) {
      is_wmo = true;
    }
    prev_arg = arg;
  }

  bool is_incremental =
      !is_wmo && !is_dump_ast && !output_file_map_path.empty();
  std::string incremental_file_map_path;
  std::set<std::string> optional_outputs;
  if (is_incremental) {
    output_file_map.ReadFromPath(output_file_map_path);
    incremental_file_map_path = std::filesystem::path(output_file_map_path)
                                    .replace_extension(".incremental.json")
                                    .string();
    output_file_map.WriteToPath(incremental_file_map_path);

    auto module = module_outputs.find("-emit-module-path");
    if (module != module_outputs.end()) {
      auto documentation = std::filesystem::path(module->second)
                               .replace_extension(".swiftdoc")
                               .string();
      output_file_map.AddOutput(documentation);
      optional_outputs.insert(documentation);
      if (!avoid_source_info &&
          !module_outputs.count("-emit-module-source-info-path")) {
        auto source_info = std::filesystem::path(module->second)
                               .replace_extension(".swiftsourceinfo")
                               .string();
        output_file_map.AddOutput(source_info);
        optional_outputs.insert(source_info);
      }
    }
  }

  // We rewrite the output paths so swiftc writes module files directly into the
  // incremental storage area. This keeps them consistent with the dependency
  // records even if the request fails before we copy the outputs back.
  prev_arg.clear();
  for (const auto& arg : request.arguments) {
    if (is_incremental && prev_arg == "-output-file-map") {
      params_file_stream << incremental_file_map_path << '\n';
    } else if (is_incremental && module_output_flags.count(prev_arg)) {
      params_file_stream << output_file_map.AddOutput(arg) << '\n';
    } else {
      params_file_stream << arg << '\n';
    }
    prev_arg = arg;
  }
  if (is_incremental) {
    params_file_stream << "-incremental\n";
  }

  processed_args.push_back("@" + params_file->GetPath());
  params_file_stream.close();

  std::ostringstream stderr_stream;

  if (is_incremental) {
    std::set<std::string> dir_paths;

    for (const auto& expected_object_pair :
         output_file_map.incremental_outputs()) {
      // Bazel creates the intermediate directories for the files declared at
      // analysis time, but we need to manually create the ones for the
      // incremental storage area.
      const std::string dir_path =
          std::filesystem::path(expected_object_pair.second)
              .parent_path()
              .string();
      dir_paths.insert(dir_path);
      dir_paths.insert(std::filesystem::path(expected_object_pair.first)
                           .parent_path()
                           .string());
    }

    for (const auto& output : output_file_map.incremental_dependencies()) {
      dir_paths.insert(std::filesystem::path(output).parent_path().string());
    }

    for (const auto& dir_path : dir_paths) {
      std::error_code ec;
      std::filesystem::create_directories(LongPath(dir_path), ec);
      if (ec) {
        stderr_stream << "swift_worker: Could not create directory " << dir_path
                      << " (" << ec.message() << ")\n";
        FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
        return;
      }
    }
  }

  SwiftRunner swift_runner(processed_args, index_import_path_,
                           /*force_response_file=*/true);
  int exit_code = swift_runner.Run(&stderr_stream, /*stdout_to_stderr=*/true);
  if (exit_code != 0) {
    FinalizeWorkRequest(request, response, exit_code, stderr_stream);
    return;
  }

  if (is_incremental) {
    // Copy the output files from the incremental storage area back to the
    // locations where Bazel declared the files.
    for (const auto& expected_object_pair :
         output_file_map.incremental_outputs()) {
      if (optional_outputs.count(expected_object_pair.first) &&
          !std::filesystem::exists(LongPath(expected_object_pair.second))) {
        continue;
      }
      std::error_code ec;
      copy_file(expected_object_pair.second, expected_object_pair.first, ec);
      if (ec) {
        stderr_stream << "swift_worker: Could not copy "
                      << expected_object_pair.second << " to "
                      << expected_object_pair.first << " (" << ec.message()
                      << ")\n";
        FinalizeWorkRequest(request, response, EXIT_FAILURE, stderr_stream);
        return;
      }
    }
  }

  FinalizeWorkRequest(request, response, exit_code, stderr_stream);
}
