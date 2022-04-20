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

#include "tools/common/file_system.h"

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <string>

#ifdef __APPLE__
#include <copyfile.h>
#else
#include <fcntl.h>
#include <sys/sendfile.h>
#endif

#include "absl/cleanup/cleanup.h"
#include "absl/status/status.h"
#include "absl/strings/string_view.h"
#include "absl/strings/substitute.h"
#include "tools/common/path_utils.h"
#include "tools/common/status.h"

namespace bazel_rules_swift {

std::string GetCurrentDirectory() {
  // Passing null,0 causes getcwd to allocate the buffer of the correct size.
  char *buffer = getcwd(nullptr, 0);
  std::string cwd(buffer);
  free(buffer);
  return cwd;
}

absl::Status CopyFile(absl::string_view src, absl::string_view dest) {
  // `string_view`s are not required to be null-terminated, so get explicit
  // null-terminated strings that we can pass to the C functions below.
  std::string null_terminated_src(src.data(), src.length());
  std::string null_terminated_dest(dest.data(), dest.length());

#ifdef __APPLE__
  // The `copyfile` function with `COPYFILE_ALL` mode preserves permissions and
  // modification time.
  if (copyfile(null_terminated_src.c_str(), null_terminated_dest.c_str(),
               nullptr, COPYFILE_ALL | COPYFILE_CLONE) == 0) {
    return absl::OkStatus();
  }
  return bazel_rules_swift::MakeStatusFromErrno(
      absl::Substitute("Could not copy $0 to $1", src, dest));
#elif __unix__
  // On Linux, we can use `sendfile` to copy it more easily than calling
  // `read`/`write` in a loop.
  auto MakeFailingStatus = [src, dest](absl::string_view reason) {
    return bazel_rules_swift::MakeStatusFromErrno(
        absl::Substitute("Could not copy $0 to $1; $2", src, dest, reason));
  };

  int src_fd = open(null_terminated_src.c_str(), O_RDONLY);
  if (!src_fd) {
    return MakeFailingStatus("could not open source for reading");
  }

  absl::Cleanup src_closer = [src_fd] { close(src_fd); };

  struct stat stat_buf;
  if (fstat(src_fd, &stat_buf) == -1) {
    return MakeFailingStatus("could not stat source file");
  }

  int dest_fd =
      open(null_terminated_dest.c_str(), O_WRONLY | O_CREAT, stat_buf.st_mode);
  if (!dest_fd) {
    return MakeFailingStatus("could not open destination for writing");
  }

  absl::Cleanup dest_closer = [dest_fd] { close(dest_fd); };

  off_t offset = 0;
  if (sendfile(dest_fd, src_fd, &offset, stat_buf.st_size) == -1) {
    return MakeFailingStatus("could not copy file data");
  }

  struct timespec timespecs[2] = {stat_buf.st_atim, stat_buf.st_mtim};
  if (futimens(dest_fd, timespecs) == -1) {
    return MakeFailingStatus("could not update destination timestamps");
  }

  return absl::OkStatus();
#else
#error Only macOS and Unix are supported.
#endif
}

absl::Status MakeDirs(absl::string_view path, int mode) {
  auto MakeFailingStatus = [path](absl::string_view reason) {
    return bazel_rules_swift::MakeStatusFromErrno(
        absl::Substitute("Could not create directory $0; $1", path, reason));
  };

  // If we got an empty string, we've recursed past the first segment in the
  // path. Assume it exists (if it doesn't, we'll fail when we try to create a
  // directory inside it).
  if (path.empty()) {
    return absl::OkStatus();
  }

  // `string_view`s are not required to be null-terminated, so get an explicit
  // null-terminated string that we can pass to the C functions below.
  std::string null_terminated_path(path.data(), path.length());

  struct stat dir_stats;
  if (stat(null_terminated_path.c_str(), &dir_stats) == 0) {
    // Return true if the directory already exists.
    if (S_ISDIR(dir_stats.st_mode)) {
      return absl::OkStatus();
    }

    return MakeFailingStatus("path already exists but is not a directory");
  }

  // Recurse to create the parent directory.
  if (absl::Status parent_status = MakeDirs(Dirname(path), mode);
      !parent_status.ok()) {
    return parent_status;
  }

  // Create the directory that was requested.
  if (mkdir(null_terminated_path.c_str(), mode) == 0) {
    return absl::OkStatus();
  }

  // Race condition: The above call to `mkdir` could fail if there are multiple
  // calls to `MakeDirs` running at the same time with overlapping paths, so
  // check again to see if the directory exists despite the call failing. If it
  // does, that's ok.
  if (errno == EEXIST && stat(null_terminated_path.c_str(), &dir_stats) == 0) {
    if (S_ISDIR(dir_stats.st_mode)) {
      return absl::OkStatus();
    }

    return MakeFailingStatus("path already exists but is not a directory");
  }

  return MakeFailingStatus("unexpected error");
}

}  // namespace bazel_rules_swift
