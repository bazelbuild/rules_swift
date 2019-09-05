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

#include <array>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "tools/common/path_utils.h"

extern char **environ;

namespace {

// Type to encapsulate pipe(2).
struct Pipe {
  Pipe() {
    auto result = pipe(pipe_.data());
    valid_ = result == 0;
  }

  Pipe(Pipe &&pipe) : pipe_(std::move(pipe.pipe_)), valid_(pipe.valid_) {
    if (valid_) {
      for (auto &fd : pipe.pipe_) {
        fd = -1;
      }
    }
  }

  bool Valid() const { return valid_; }

  // Pipes are movable only.
  Pipe(const Pipe &) = delete;
  Pipe &operator=(const Pipe &) = delete;

  ~Pipe() {
    if (valid_) {
      for (const auto fd : pipe_) {
        if (fd > 0) {
          close(fd);
        }
      }
    }
  }

  void CloseWriteEnd() {
    auto &fd = pipe_[1];
    if (fd > 0) {
      close(fd);
      fd = -1;
    }
  }

  int ReadFD() const { return pipe_[0]; }
  int WriteFD() const { return pipe_[1]; }

private:
  std::array<int, 2> pipe_;
  bool valid_;
};

// An RAII class that manages the pipes and posix_spawn state needed to redirect
// subprocess I/O. Currently supports stdout and stderr, but can be extended to
// handle stdin if needed.
class PosixSpawnIORedirector {
 public:
  // Create an I/O redirector that can be used with posix_spawn to capture
  // stdout and stderr.
  static std::unique_ptr<PosixSpawnIORedirector> Create(bool stdoutToStderr) {
    Pipe stdout_pipe;
    Pipe stderr_pipe;
    if (!stdout_pipe.Valid() || !stderr_pipe.Valid()) {
      return nullptr;
    }

    return std::unique_ptr<PosixSpawnIORedirector>(new PosixSpawnIORedirector(
        std::move(stdout_pipe), std::move(stderr_pipe), stdoutToStderr));
  }

  // Explicitly make PosixSpawnIORedirector non-copyable and movable.
  PosixSpawnIORedirector(const PosixSpawnIORedirector &) = delete;
  PosixSpawnIORedirector &operator=(const PosixSpawnIORedirector &) = delete;
  PosixSpawnIORedirector(PosixSpawnIORedirector &&) = default;
  PosixSpawnIORedirector &operator=(PosixSpawnIORedirector &&) = default;

  ~PosixSpawnIORedirector() {
    posix_spawn_file_actions_destroy(&file_actions_);
  }

  // Returns the pointer to a posix_spawn_file_actions_t value that should be
  // passed to posix_spawn to enable this redirection.
  posix_spawn_file_actions_t *PosixSpawnFileActions() { return &file_actions_; }

  // Consumes all the data output to stdout and stderr by the subprocess and
  // writes it to the respective output stream.
  void ConsumeAllSubprocessOutput(std::ostream *stdout_stream,
                                  std::ostream *stderr_stream);

private:
  explicit PosixSpawnIORedirector(Pipe &&stdout_pipe, Pipe &&stderr_pipe,
                                  bool stdoutToStderr)
      : stdout_pipe_(std::move(stdout_pipe)),
        stderr_pipe_(std::move(stderr_pipe)) {
    posix_spawn_file_actions_init(&file_actions_);

    if (stdoutToStderr) {
      posix_spawn_file_actions_adddup2(&file_actions_, stderr_pipe_.WriteFD(),
                                       STDOUT_FILENO);
    } else {
      posix_spawn_file_actions_adddup2(&file_actions_, stdout_pipe_.WriteFD(),
                                       STDOUT_FILENO);
    }
    posix_spawn_file_actions_adddup2(&file_actions_, stderr_pipe_.WriteFD(),
                                     STDERR_FILENO);

    posix_spawn_file_actions_addclose(&file_actions_, stdout_pipe_.ReadFD());
    posix_spawn_file_actions_addclose(&file_actions_, stdout_pipe_.WriteFD());
    posix_spawn_file_actions_addclose(&file_actions_, stderr_pipe_.ReadFD());
    posix_spawn_file_actions_addclose(&file_actions_, stderr_pipe_.WriteFD());
  }

  Pipe stdout_pipe_;
  Pipe stderr_pipe_;
  posix_spawn_file_actions_t file_actions_;
};

void PosixSpawnIORedirector::ConsumeAllSubprocessOutput(
    std::ostream *stdout_stream, std::ostream *stderr_stream) {
  // The parent process doesn't write to the pipes.
  stdout_pipe_.CloseWriteEnd();
  stderr_pipe_.CloseWriteEnd();

  std::vector<pollfd> polls;
  if (stdout_stream) {
    polls.push_back({stdout_pipe_.ReadFD(), POLLIN});
  }
  if (stderr_stream) {
    polls.push_back({stderr_pipe_.ReadFD(), POLLIN});
  }

  char buffer[1024];
  int status;
  while ((status = poll(polls.data(), polls.size(), -1)) > 0) {
    for (const auto &pipe_poll : polls) {
      if (!pipe_poll.revents) {
        continue;
      }

      int bytes_read = read(pipe_poll.fd, buffer, sizeof(buffer));
      if (bytes_read == 0) {
        // End of file.
        return;
      }

      if (pipe_poll.fd == stdout_pipe_.ReadFD()) {
        stdout_stream->write(buffer, bytes_read);
      } else if (pipe_poll.fd == stderr_pipe_.ReadFD()) {
        stderr_stream->write(buffer, bytes_read);
      }
    }
  }
}

// Converts an array of string arguments to char *arguments.
// The first arg is reduced to its basename as per execve conventions.
// Note that the lifetime of the char* arguments in the returned array
// are controlled by the lifetime of the strings in args.
std::vector<const char *> ConvertToCArgs(const std::vector<std::string> &args) {
  std::vector<const char *> c_args;
  c_args.push_back(Basename(args[0].c_str()));
  for (int i = 1; i < args.size(); i++) {
    c_args.push_back(args[i].c_str());
  }
  c_args.push_back(nullptr);
  return c_args;
}

}  // namespace

void ExecProcess(const std::vector<std::string> &args) {
  std::vector<const char *> exec_argv = ConvertToCArgs(args);
  execv(args[0].c_str(), const_cast<char **>(exec_argv.data()));
  std::cerr << "Error executing child process.'" << args[0] << "'. "
            << strerror(errno) << "\n";
  abort();
}

int RunSubProcess(const std::vector<std::string> &args,
                  std::ostream *stdout_stream, std::ostream *stderr_stream,
                  bool stdout_to_stderr) {
  std::vector<const char *> exec_argv = ConvertToCArgs(args);

  // Set up a pipe to redirect stderr from the child process so that we can
  // capture it and return it in the response message.
  std::unique_ptr<PosixSpawnIORedirector> redirector =
      PosixSpawnIORedirector::Create(stdout_to_stderr);
  if (!redirector) {
    (*stderr_stream) << "Error creating stderr pipe for child process.\n";
    return 254;
  }

  pid_t pid;
  int status =
      posix_spawn(&pid, args[0].c_str(), redirector->PosixSpawnFileActions(),
                  nullptr, const_cast<char **>(exec_argv.data()), environ);
  redirector->ConsumeAllSubprocessOutput(stdout_stream, stderr_stream);

  if (status == 0) {
    int wait_status;
    do {
      wait_status = waitpid(pid, &status, 0);
    } while ((wait_status == -1) && (errno == EINTR));

    if (wait_status < 0) {
      std::cerr << "Error waiting on child process '" << args[0] << "'. "
                << strerror(errno) << "\n";
      return wait_status;
    }

    int exit_status = WEXITSTATUS(status);
    if (exit_status != 0) {
      return exit_status;
    }
    return 0;
  } else {
    std::cerr << "Error forking process '" << args[0] << "'. "
              << strerror(status) << "\n";
    return status;
  }
}
