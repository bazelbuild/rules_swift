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

#include "tools/common/path_utils.h"

namespace {

static std::string RealPath(const std::string &src) {
  // Passing path,null causes realpath to allocate the buffer of the correct size.
  char *buffer = realpath(src.c_str(), nullptr);
  std::string realpath(buffer);
  free(buffer);
  return realpath;
}

}  // namespace

std::string GetCurrentDirectory() {
  // Passing null,0 causes getcwd to allocate the buffer of the correct size.
  char *buffer = getcwd(nullptr, 0);
  std::string cwd(buffer);
  free(buffer);
  return cwd;
}

bool CopyFile(const std::string &src, const std::string &dest) {
#ifdef __APPLE__
  // The `copyfile` function with `COPYFILE_ALL` mode preserves permissions and
  // modification time.
  return copyfile(src.c_str(), dest.c_str(), nullptr,
                  COPYFILE_ALL | COPYFILE_CLONE) == 0;
#elif __unix__
  // On Linux, we can use `sendfile` to copy it more easily than calling
  // `read`/`write` in a loop.
  struct stat stat_buf;
  bool success = false;

  int src_fd = open(src.c_str(), O_RDONLY);
  if (src_fd) {
    fstat(src_fd, &stat_buf);

    int dest_fd = open(dest.c_str(), O_WRONLY | O_CREAT, stat_buf.st_mode);
    if (dest_fd) {
      off_t offset = 0;
      if (sendfile(dest_fd, src_fd, &offset, stat_buf.st_size) != -1) {
        struct timespec timespecs[2] = {stat_buf.st_atim, stat_buf.st_mtim};
        futimens(dest_fd, timespecs);
        success = true;
      }
      close(dest_fd);
    }
    close(src_fd);
  }
  return success;
#else
// TODO(allevato): If we want to support Windows in the future, we'll need to
// use something like `CopyFileA`.
#error Only macOS and Unix are supported at this time.
#endif
}

std::string MakePathAbsolute(const std::string &arg) {
  if (arg.find("__BAZEL_PWD__/", 0) == 0) {
    // If "__BAZEL_PWD__/"" is at the start of a path it's replaced with the
    // current directory and is then realpath'ed. This implements the
    // swift.absolute_source_files feature.
    return RealPath(GetCurrentDirectory() + arg.substr(13, std::string::npos));
  } else {
    return arg;
  }
}

bool MakeDirs(const std::string &path, int mode) {
  // If we got an empty string, we've recursed past the first segment in the
  // path. Assume it exists (if it doesn't, we'll fail when we try to create a
  // directory inside it).
  if (path.empty()) {
    return true;
  }

  struct stat dir_stats;
  if (stat(path.c_str(), &dir_stats) == 0) {
    // Return true if the directory already exists.
    return S_ISDIR(dir_stats.st_mode);
  }

  // Recurse to create the parent directory.
  if (!MakeDirs(Dirname(path).c_str(), mode)) {
    return false;
  }

  // Create the directory that was requested.
  return mkdir(path.c_str(), mode) == 0;
}
