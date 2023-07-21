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

#include <fcntl.h>
#include <spawn.h>
#include <sys/poll.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "absl/cleanup/cleanup.h"
#include "absl/container/flat_hash_map.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/str_split.h"
#include "tools/common/path_utils.h"

extern char **environ;

namespace bazel_rules_swift {

namespace {

// An RAII class that manages the pipes and posix_spawn state needed to redirect
// subprocess I/O. Currently only supports stderr, but can be extended to handle
// stdin and stdout if needed.
class PosixSpawnIORedirector {
 public:
  // Create an I/O redirector that can be used with posix_spawn to capture
  // stderr.
  static std::unique_ptr<PosixSpawnIORedirector> Create(bool stdout_to_stderr) {
    int stderr_pipe[2];
    if (pipe(stderr_pipe) != 0) {
      return nullptr;
    }

    return std::unique_ptr<PosixSpawnIORedirector>(
        new PosixSpawnIORedirector(stderr_pipe, stdout_to_stderr));
  }

  // Explicitly make PosixSpawnIORedirector non-copyable and movable.
  PosixSpawnIORedirector(const PosixSpawnIORedirector &) = delete;
  PosixSpawnIORedirector &operator=(const PosixSpawnIORedirector &) = delete;
  PosixSpawnIORedirector(PosixSpawnIORedirector &&) = default;
  PosixSpawnIORedirector &operator=(PosixSpawnIORedirector &&) = default;

  ~PosixSpawnIORedirector() {
    SafeClose(stderr_pipe_[0]);
    SafeClose(stderr_pipe_[1]);
    posix_spawn_file_actions_destroy(&file_actions_);
  }

  // Returns the pointer to a posix_spawn_file_actions_t value that should be
  // passed to posix_spawn to enable this redirection.
  posix_spawn_file_actions_t *PosixSpawnFileActions() { return &file_actions_; }

  // Returns a pointer to the two-element file descriptor array for the stderr
  // pipe.
  int *StderrPipe() { return stderr_pipe_; }

  // Consumes all the data output to stderr by the subprocess and writes it to
  // the given output stream.
  void ConsumeAllSubprocessOutput(std::ostream &stderr_stream);

 private:
  explicit PosixSpawnIORedirector(int stderr_pipe[], bool stdout_to_stderr) {
    memcpy(stderr_pipe_, stderr_pipe, sizeof(int) * 2);

    posix_spawn_file_actions_init(&file_actions_);
    posix_spawn_file_actions_addclose(&file_actions_, stderr_pipe_[0]);
    if (stdout_to_stderr) {
      posix_spawn_file_actions_adddup2(&file_actions_, stderr_pipe_[1],
                                       STDOUT_FILENO);
    }
    posix_spawn_file_actions_adddup2(&file_actions_, stderr_pipe_[1],
                                     STDERR_FILENO);
    posix_spawn_file_actions_addclose(&file_actions_, stderr_pipe_[1]);
  }

  // Closes a file descriptor only if it hasn't already been closed.
  void SafeClose(int &fd) {
    if (fd >= 0) {
      close(fd);
      fd = -1;
    }
  }

  int stderr_pipe_[2];
  posix_spawn_file_actions_t file_actions_;
};

void PosixSpawnIORedirector::ConsumeAllSubprocessOutput(
    std::ostream &stderr_stream) {
  SafeClose(stderr_pipe_[1]);

  char stderr_buffer[1024];
  pollfd stderr_poll = {stderr_pipe_[0], POLLIN};
  int status;
  while ((status = poll(&stderr_poll, 1, -1)) > 0) {
    if (stderr_poll.revents) {
      int bytes_read =
          read(stderr_pipe_[0], stderr_buffer, sizeof(stderr_buffer));
      if (bytes_read == 0) {
        break;
      }
      stderr_stream.write(stderr_buffer, bytes_read);
    }
  }
}

// Converts an array of string arguments to char *arguments.
// The first arg is reduced to its basename as per execve conventions.
// Note that the lifetime of the char* arguments in the returned array
// are controlled by the lifetime of the strings in args.
std::vector<const char *> ConvertToCArgs(const std::vector<std::string> &args) {
  std::vector<const char *> c_args;
  c_args.push_back(Basename(args[0].c_str()).data());
  for (int i = 1; i < args.size(); i++) {
    c_args.push_back(args[i].c_str());
  }
  c_args.push_back(nullptr);
  return c_args;
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
                  std::ostream &stderr_stream, bool stdout_to_stderr) {
  // Set up a pipe to redirect stderr from the child process so that we can
  // capture it and return it in the response message.
  std::unique_ptr<PosixSpawnIORedirector> redirector =
      PosixSpawnIORedirector::Create(stdout_to_stderr);
  if (!redirector) {
    stderr_stream << "Error creating stderr pipe for child process."
                  << std::endl;
    return 254;
  }

  std::vector<const char *> exec_argv = ConvertToCArgs(args);

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

  absl::Cleanup c = [&new_environ] {
    for (char *envp : new_environ) {
      free(envp);
    }
  };

  pid_t pid;
  int status =
      posix_spawn(&pid, args[0].c_str(), redirector->PosixSpawnFileActions(),
                  nullptr, const_cast<char **>(exec_argv.data()), envp);
  redirector->ConsumeAllSubprocessOutput(stderr_stream);

  if (status == 0) {
    int wait_status;
    do {
      wait_status = waitpid(pid, &status, 0);
    } while ((wait_status == -1) && (errno == EINTR));

    if (wait_status < 0) {
      std::cerr << "Error waiting on child process '" << args[0] << "'. "
                << strerror(errno) << std::endl;
      return wait_status;
    }

    if (WIFEXITED(status)) {
      return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
      return WTERMSIG(status);
    }

    // If we get here, we should add a case to handle it above instead.
    return 42;
  } else {
    std::cerr << "Error forking process '" << args[0] << "'. "
              << strerror(status) << std::endl;
    return status;
  }
}

}  // namespace bazel_rules_swift
