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

#include "tools/common/process.h"

#include <fcntl.h>
#include <spawn.h>
#include <sys/poll.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <future>  // NOLINT
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "absl/container/flat_hash_map.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_split.h"
#include "absl/strings/string_view.h"
#include "tools/common/temp_file.h"

extern char **environ;

namespace bazel_rules_swift {

namespace {

// Converts an array of string arguments to char *arguments, terminated by a
// nullptr.
// It is the responsibility of the caller to free the elements of the returned
// vector.
std::vector<char *> ConvertToCArgs(const std::vector<std::string> &args) {
  std::vector<char *> c_args;
  c_args.reserve(args.size() + 1);
  for (int i = 0; i < args.size(); i++) {
    c_args.push_back(strdup(args[i].c_str()));
  }
  c_args.push_back(nullptr);
  return c_args;
}

// An RAII class that manages the pipes and posix_spawn state needed to redirect
// subprocess I/O. Currently only supports stdout and stderr, but can be
// extended to handle stdin if needed.
class PosixSpawnIORedirector {
 public:
  // Create an I/O redirector that can be used with posix_spawn to capture
  // stderr.
  static std::unique_ptr<PosixSpawnIORedirector> Create();

  // Explicitly make PosixSpawnIORedirector non-copyable and movable.
  PosixSpawnIORedirector(const PosixSpawnIORedirector &) = delete;
  PosixSpawnIORedirector &operator=(const PosixSpawnIORedirector &) = delete;
  PosixSpawnIORedirector(PosixSpawnIORedirector &&) = default;
  PosixSpawnIORedirector &operator=(PosixSpawnIORedirector &&) = default;

  ~PosixSpawnIORedirector();

  // Returns the pointer to a posix_spawn_file_actions_t value that should be
  // passed to posix_spawn to enable this redirection.
  posix_spawn_file_actions_t *PosixSpawnFileActions() { return &file_actions_; }

  // Returns a pointer to the two-element file descriptor array for the stdout
  // pipe.
  int *StdoutPipe() { return stdout_pipe_; }

  // Returns a pointer to the two-element file descriptor array for the stderr
  // pipe.
  int *StderrPipe() { return stderr_pipe_; }

  // Consumes all the data output to stdout and stderr by the subprocess and
  // writes it to the given output stream.
  void ConsumeAllSubprocessOutput(std::ostream &stdout_stream,
                                  std::ostream &stderr_stream);

 private:
  PosixSpawnIORedirector(int stdout_pipe[], int stderr_pipe[]);

  // Closes a file descriptor only if it hasn't already been closed.
  void SafeClose(int &fd) {
    if (fd >= 0) {
      close(fd);
      fd = -1;
    }
  }

  int stdout_pipe_[2];
  int stderr_pipe_[2];
  posix_spawn_file_actions_t file_actions_;
};

PosixSpawnIORedirector::PosixSpawnIORedirector(int stdout_pipe[],
                                               int stderr_pipe[]) {
  memcpy(stdout_pipe_, stdout_pipe, sizeof(int) * 2);
  memcpy(stderr_pipe_, stderr_pipe, sizeof(int) * 2);

  posix_spawn_file_actions_init(&file_actions_);
  posix_spawn_file_actions_addclose(&file_actions_, stdout_pipe_[0]);
  posix_spawn_file_actions_addclose(&file_actions_, stderr_pipe_[0]);
  posix_spawn_file_actions_adddup2(&file_actions_, stdout_pipe_[1],
                                   STDOUT_FILENO);
  posix_spawn_file_actions_adddup2(&file_actions_, stderr_pipe_[1],
                                   STDERR_FILENO);
  posix_spawn_file_actions_addclose(&file_actions_, stdout_pipe_[1]);
  posix_spawn_file_actions_addclose(&file_actions_, stderr_pipe_[1]);
}

PosixSpawnIORedirector::~PosixSpawnIORedirector() {
  SafeClose(stdout_pipe_[1]);
  SafeClose(stderr_pipe_[1]);
  posix_spawn_file_actions_destroy(&file_actions_);
}

std::unique_ptr<PosixSpawnIORedirector> PosixSpawnIORedirector::Create() {
  int stdout_pipe[2];
  int stderr_pipe[2];
  if (pipe(stdout_pipe) != 0 || pipe(stderr_pipe) != 0) {
    return nullptr;
  }

  return std::unique_ptr<PosixSpawnIORedirector>(
      new PosixSpawnIORedirector(stdout_pipe, stderr_pipe));
}

void PosixSpawnIORedirector::ConsumeAllSubprocessOutput(
    std::ostream &stdout_stream, std::ostream &stderr_stream) {
  SafeClose(stdout_pipe_[1]);
  SafeClose(stderr_pipe_[1]);

  char stdout_buffer[1024];
  char stderr_buffer[1024];

  std::vector<pollfd> poll_list{
      {stdout_pipe_[0], POLLIN},
      {stderr_pipe_[0], POLLIN},
  };

  bool active_events = true;
  while (active_events) {
    active_events = false;
    while (poll(&poll_list.front(), poll_list.size(), -1) == -1) {
      int err = errno;
      if (err == EAGAIN || err == EINTR) {
        continue;
      }
    }
    if (poll_list[0].revents & POLLIN) {
      int bytes_read =
          read(stdout_pipe_[0], stdout_buffer, sizeof(stdout_buffer));
      if (bytes_read > 0) {
        stdout_stream.write(stdout_buffer, bytes_read);
        active_events = true;
      }
    }
    if (poll_list[1].revents & POLLIN) {
      int bytes_read =
          read(stderr_pipe_[0], stderr_buffer, sizeof(stderr_buffer));
      if (bytes_read > 0) {
        stderr_stream.write(stderr_buffer, bytes_read);
        active_events = true;
      }
    }
  }
}

}  // namespace

absl::flat_hash_map<std::string, std::string> GetCurrentEnvironment() {
  absl::flat_hash_map<std::string, std::string> result;
  char **envp = environ;
  while (*envp++ != nullptr) {
    std::pair<absl::string_view, absl::string_view> key_value =
        absl::StrSplit(*envp, absl::MaxSplits('=', 1));
    result[key_value.first] = std::string(key_value.second);
  }
  return result;
}

int RunSubProcess(const std::vector<std::string> &args,
                  const absl::flat_hash_map<std::string, std::string> *env,
                  std::ostream &stdout_stream, std::ostream &stderr_stream) {
  absl::StatusOr<std::unique_ptr<AsyncProcess>> process =
      AsyncProcess::Spawn(args, nullptr, env);
  if (!process.ok()) {
    stderr_stream << "error spawning subprocess: " << process.status() << "\n";
    return 254;
  }
  absl::StatusOr<AsyncProcess::Result> result =
      (*process)->WaitForTermination();
  if (!result.ok()) {
    stderr_stream << "error waiting for subprocess: " << result.status()
                  << "\n";
    return 254;
  }
  stdout_stream << result->stdout;
  stderr_stream << result->stderr;
  return result->exit_code;
}

AsyncProcess::AsyncProcess(
    pid_t pid, std::vector<char *> argv,
    std::unique_ptr<TempFile> response_file,
    std::vector<char *> allocated_environ,
    std::future<std::pair<std::string, std::string>> output)
    : pid_(pid),
      argv_(argv),
      response_file_(std::move(response_file)),
      allocated_environ_(std::move(allocated_environ)),
      output_(std::move(output)) {}

AsyncProcess::~AsyncProcess() {
  for (char *arg : argv_) {
    free(arg);
  }
  for (char *envp : allocated_environ_) {
    free(envp);
  }
}

absl::StatusOr<std::unique_ptr<AsyncProcess>> AsyncProcess::Spawn(
    const std::vector<std::string> &normal_args,
    std::unique_ptr<TempFile> response_file,
    const absl::flat_hash_map<std::string, std::string> *env) {
  // Set up a pipe to redirect stdout and stderr from the child process so that
  // we can redirect them to the given streams.
  std::unique_ptr<PosixSpawnIORedirector> redirector =
      PosixSpawnIORedirector::Create();
  if (!redirector) {
    return absl::UnknownError("Failed to create pipes for child process");
  }

  std::vector<char *> exec_argv = ConvertToCArgs(normal_args);
  if (response_file) {
    exec_argv.back() =
        strdup(absl::StrCat("@", response_file->GetPath()).c_str());
    exec_argv.push_back(nullptr);
  }

  char **envp;
  std::vector<char *> new_environ;
  if (env) {
    // Copy the environment as an array of C strings, with guaranteed cleanup
    // below whenever we exit.
    for (const auto &[key, value] : *env) {
      new_environ.push_back(strdup(absl::StrCat(key, "=", value).c_str()));
    }
    new_environ.push_back(nullptr);
    envp = new_environ.data();
  } else {
    // If no environment was passed, use the current process's verbatim.
    envp = environ;
  }

  pid_t pid;
  int result =
      posix_spawn(&pid, exec_argv[0], redirector->PosixSpawnFileActions(),
                  nullptr, exec_argv.data(), envp);
  if (result != 0) {
    return absl::Status(absl::ErrnoToStatusCode(errno),
                        "Failed to spawn child process");
  }

  // Start an asynchronous task in the background that reads the output from the
  // stdout/stderr pipes while the process is running.
  std::future<std::pair<std::string, std::string>> output =
      std::async(std::launch::async, [r = std::move(redirector)]() {
        std::ostringstream stdout_output;
        std::ostringstream stderr_output;
        r->ConsumeAllSubprocessOutput(stdout_output, stderr_output);
        return std::make_pair(stdout_output.str(), stderr_output.str());
      });
  return std::unique_ptr<AsyncProcess>(
      new AsyncProcess(pid, exec_argv, std::move(response_file), new_environ,
                       std::move(output)));
}

absl::StatusOr<AsyncProcess::Result> AsyncProcess::WaitForTermination() {
  int status;
  int wait_status;
  do {
    wait_status = waitpid(pid_, &status, 0);
  } while ((wait_status == -1) && (errno == EINTR));

  // Once the process has terminated, wait for the output to be read and prepare
  // the result.
  std::pair<std::string, std::string> output = output_.get();
  Result result{0, std::move(output.first), std::move(output.second)};

  if (wait_status < 0) {
    return absl::Status(absl::ErrnoToStatusCode(errno),
                        "error waiting on child process");
  }
  if (WIFEXITED(status)) {
    result.exit_code = WEXITSTATUS(status);
    return result;
  }
  if (WIFSIGNALED(status)) {
    result.exit_code = WTERMSIG(status);
    return result;
  }
  // If we get here, we should add a case to handle it above instead.
  return absl::UnknownError(absl::StrCat("Unexpected wait status: ", status));
}

}  // namespace bazel_rules_swift
