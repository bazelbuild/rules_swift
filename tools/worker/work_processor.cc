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

#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

#include "tools/common/temp_file.h"
#include "tools/worker/swift_runner.h"
#include "tools/worker/worker_protocol.h"

namespace {

static void FinalizeWorkRequest(
    const bazel_rules_swift::worker_protocol::WorkRequest &request,
    bazel_rules_swift::worker_protocol::WorkResponse &response, int exit_code,
    const std::ostringstream &output) {
  response.exit_code = exit_code;
  response.output = output.str();
  response.request_id = request.request_id;
  response.was_cancelled = false;
}

};  // end namespace

WorkProcessor::WorkProcessor(const std::vector<std::string> &args,
                             std::string index_import_path)
    : index_import_path_(index_import_path) {
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
  auto params_file = TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream params_file_stream(params_file->GetPath());

  // Simply pass all arguments through to the compiler without modification
  for (const std::string &arg : request.arguments) {
    params_file_stream << arg << '\n';
  }

  processed_args.push_back("@" + params_file->GetPath());
  params_file_stream.close();

  std::ostringstream stderr_stream;

  SwiftRunner swift_runner(processed_args, index_import_path_,
                           /*force_response_file=*/true);
  int exit_code = swift_runner.Run(&stderr_stream, /*stdout_to_stderr=*/true);

  FinalizeWorkRequest(request, response, exit_code, stderr_stream);
}
