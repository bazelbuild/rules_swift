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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_WORK_PROCESSOR_H
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_WORK_PROCESSOR_H

#include <map>
#include <string>
#include <vector>

#include "third_party/bazel_protos/worker_protocol.pb.h"

// Manages persistent global state for the Swift worker and processes individual
// work requests.
class WorkProcessor {
 public:
  // Initializes a new work processor with the given universal arguments from
  // the job invocation.
  WorkProcessor(const std::vector<std::string> &args);

  // Processes the given work request and writes its exit code and stderr output
  // (if any) into the given response.
  void ProcessWorkRequest(const blaze::worker::WorkRequest &request,
                          blaze::worker::WorkResponse *response);

 private:
  std::vector<std::string> universal_args_;
};

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_WORK_PROCESSOR_H
