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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_WRAPPERS_PROCESS_H
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_WRAPPERS_PROCESS_H

#include <string>
#include <vector>

#include "absl/container/flat_hash_map.h"

namespace bazel_rules_swift {

// Spawns a subprocess for given arguments args and waits for it to terminate.
// The first element in args is used for the executable path. If env is nullptr,
// then the current process's environment is used; otherwise, the new
// environment is used. If stdout_to_stderr is set, then stdout is redirected to
// the stderr stream as well. Returns the exit code of the spawned process.
int RunSubProcess(const std::vector<std::string> &args,
                  const absl::flat_hash_map<std::string, std::string> *env,
                  std::ostream &stderr_stream, bool stdout_to_stderr = false);

// Returns a hash map containing the current process's environment.
absl::flat_hash_map<std::string, std::string> GetCurrentEnvironment();

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WRAPPERS_PROCESS_H
