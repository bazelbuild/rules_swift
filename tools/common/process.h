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

#include <spawn.h>

#include <future>  // NOLINT
#include <memory>
#include <ostream>
#include <string>
#include <utility>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/status/statusor.h"
#include "tools/common/temp_file.h"

namespace bazel_rules_swift {

// Spawns a subprocess for given arguments args and waits for it to terminate.
// The first element in args is used for the executable path. If env is nullptr,
// then the current process's environment is used; otherwise, the new
// environment is used. Returns the exit code of the spawned process. It is a
// convenience wrapper around `AsyncProcess::Spawn` and
// `AsyncProcess::WaitForTermination`.
int RunSubProcess(const std::vector<std::string> &args,
                  const absl::flat_hash_map<std::string, std::string> *env,
                  std::ostream &stdout_stream, std::ostream &stderr_stream);

// Returns a hash map containing the current process's environment.
absl::flat_hash_map<std::string, std::string> GetCurrentEnvironment();

// A wrapper around a subprocess that, when spawned, runs and reads stdout and
// stderr asynchronously.
class AsyncProcess {
 public:
  // A value containing the result of the subprocess's execution.
  struct Result {
    int exit_code;
    std::string stdout;
    std::string stderr;
  };

  // Spawns a subprocess with the given arguments, an optional response file
  // containing additional arguments, and an optional environment. If the
  // response file is provided, the `AsyncProcess` will take ownership of it and
  // ensure that it is not deleted until the lifetime of the `AsyncSubprocess`
  // has ended. If `env == nullptr`, the current process's environment is
  // inherited.
  static absl::StatusOr<std::unique_ptr<AsyncProcess>> Spawn(
      const std::vector<std::string> &normal_args,
      std::unique_ptr<TempFile> response_file,
      const absl::flat_hash_map<std::string, std::string> *env);

  // Explicitly make `AsyncProcess` non-copyable and movable.
  AsyncProcess(const AsyncProcess &) = delete;
  AsyncProcess &operator=(const AsyncProcess &) = delete;
  AsyncProcess(AsyncProcess &&) = default;
  AsyncProcess &operator=(AsyncProcess &&) = default;

  ~AsyncProcess();

  // Waits for the subprocess to terminate and returns its exit code.
  absl::StatusOr<Result> WaitForTermination();

 private:
  // Constructs a new AsyncProcess; only used by the `Spawn` factory function.
  AsyncProcess(pid_t pid, std::vector<char *> argv,
               std::unique_ptr<TempFile> response_file,
               std::vector<char *> allocated_environ,
               std::future<std::pair<std::string, std::string>> output);

  // The pid of the spawned subprocess.
  pid_t pid_;

  // The arguments to the subprocess, which must remain valid for the lifetime
  // of the process.
  std::vector<char *> argv_;

  // The response file containing additional arguments to pass to the
  // subprocess, which must remain valid for the lifetime of the process.
  std::unique_ptr<TempFile> response_file_;

  // The environment variables to set when launching the subprocess, which must
  // remain valid for the lifetime of the process.
  std::vector<char *> allocated_environ_;

  // The I/O redirector that captures the subprocess's stdout and stderr.
  std::future<std::pair<std::string, std::string>> output_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WRAPPERS_PROCESS_H
