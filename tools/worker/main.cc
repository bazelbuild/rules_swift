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

#include <algorithm>
#include <iostream>
#include <string>
#include <vector>

#include "tools/common/process.h"
#include "tools/cpp/runfiles/runfiles.h"
#include "tools/worker/swift_runner.h"

using bazel::tools::cpp::runfiles::Runfiles;

int main(int argc, char *argv[]) {
  std::string index_import_path;

  // Find the index-import tool from runfiles if available
  #ifdef BAZEL_CURRENT_REPOSITORY
    std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], BAZEL_CURRENT_REPOSITORY));
  #else
    std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0]));
  #endif

  if (runfiles != nullptr) {
    // TODO: Remove once we drop support for Xcode 16.x.
    // Determine which version of index-import to use based on the environment
    auto env = GetCurrentEnvironment();
    if (env.find("__RULES_SWIFT_USE_LEGACY_INDEX_IMPORT") != env.end()) {
      index_import_path = runfiles->Rlocation(
          "build_bazel_rules_swift_index_import_5_8/index-import");
    } else {
      index_import_path = runfiles->Rlocation(
          "build_bazel_rules_swift_index_import_6_1/index-import");
    }
  }

  auto args = std::vector<std::string>(argv + 1, argv + argc);

  // Filter out the --persistent_worker flag if present (no longer supported)
  args.erase(std::remove(args.begin(), args.end(), "--persistent_worker"), args.end());

  // Run the Swift compiler with the provided arguments
  return SwiftRunner(args, index_import_path)
      .Run(&std::cerr, /*stdout_to_stderr=*/false);
}