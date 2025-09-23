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

#include "tools/worker/compile_with_worker.h"

#include <iostream>
#include <optional>

#include "tools/worker/work_processor.h"
#include "tools/worker/worker_protocol.h"


int CompileWithWorker(const std::vector<std::string> &args,
                      std::string index_import_path) {
  // Pass the "universal arguments" to the Swift work processor. They will be
  // rewritten to replace any placeholders if necessary, and then passed at the
  // beginning of any process invocation. Note that these arguments include the
  // tool itself (i.e., "swiftc").
  WorkProcessor swift_worker(args, index_import_path);

  while (true) {
    std::optional<bazel_rules_swift::worker_protocol::WorkRequest> request =
        bazel_rules_swift::worker_protocol::ReadWorkRequest(std::cin);
    if (!request) {
      std::cerr << "Could not read WorkRequest from stdin. Killing worker "
                << "process.\n";
      return 254;
    }

    bazel_rules_swift::worker_protocol::WorkResponse response;
    swift_worker.ProcessWorkRequest(*request, response);

    bazel_rules_swift::worker_protocol::WriteWorkResponse(response, std::cout);
  }

  return 0;
}
