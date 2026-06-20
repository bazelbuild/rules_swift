// Copyright 2026 The Bazel Authors. All rights reserved.
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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_PCM_HERMETIC_RUNNER_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_PCM_HERMETIC_RUNNER_H_

#include <iostream>
#include <map>
#include <string>
#include <vector>

// Runs a Swift `-emit-pcm` invocation in a way that keeps the resulting PCM
// free of non-hermetic paths (absolute SDK location, developer dir, etc.).
//
// This is intentionally self-contained: everything the hermeticization
// flow needs lives in this one `.h`/`.cc` pair, so that when upstream Swift
// fixes PCM path handling we can drop the whole thing.
//
// High-level flow:
//   1. Invoke `swiftc -### <args>` so the driver prints the frontend command
//      without running it.
//   2. Parse the frontend command, strip flags we do not need, and rewrite
//      any absolute SDK path to a workspace-relative symlink we manage.
//   3. Run the rewritten frontend command.
int RunHermeticPcm(const std::vector<std::string>& args,
                   std::map<std::string, std::string>* env,
                   std::ostream* stderr_stream);

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_PCM_HERMETIC_RUNNER_H_
