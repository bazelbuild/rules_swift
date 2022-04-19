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

#include <string>
#include <vector>

#include "absl/algorithm/container.h"
#include "tools/worker/compile_with_worker.h"
#include "tools/worker/compile_without_worker.h"

int main(int argc, char *argv[]) {
  auto args = std::vector<std::string>(argv + 1, argv + argc);

  // When Bazel invokes a tool in persistent worker mode, it includes the flag
  // "--persistent_worker" on the command line (typically the first argument,
  // but we don't want to rely on that). Since this "worker" tool also supports
  // a non-worker mode, we can detect the mode based on the presence of this
  // flag.
  if (auto persistent_worker_flag = absl::c_find(args, "--persistent_worker");
      persistent_worker_flag != args.end()) {
    // Remove the special flag before starting the worker processing loop.
    args.erase(persistent_worker_flag);
    return bazel_rules_swift::CompileWithWorker(args);
  }

  return bazel_rules_swift::CompileWithoutWorker(args);
}
