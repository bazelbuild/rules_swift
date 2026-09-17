// Copyright 2018 The Bazel Authors. All rights reserved.
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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TEMP_FILE_H
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TEMP_FILE_H

#include <string.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <string>

#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

// An RAII temporary file.
class TempFile {
 public:
  // Create a new temporary file using the given path template string (the same
  // form used by `mkstemp`). The file will automatically be deleted when the
  // object goes out of scope.
  static std::unique_ptr<TempFile> Create(absl::string_view path_template) {
    absl::string_view tmp_dir;
    if (const char *env_value = getenv("TMPDIR")) {
      tmp_dir = env_value;
    } else {
      tmp_dir = "/tmp";
    }
    std::string path = absl::StrCat(tmp_dir, "/", path_template);
    if (mkstemp(const_cast<char *>(path.c_str())) == -1) {
      std::cerr << "Failed to create temporary file '" << path
                << "': " << strerror(errno) << std::endl;
      return nullptr;
    }
    return std::unique_ptr<TempFile>(new TempFile(path));
  }

  // Explicitly make TempFile non-copyable and movable.
  TempFile(const TempFile &) = delete;
  TempFile &operator=(const TempFile &) = delete;
  TempFile(TempFile &&) = default;
  TempFile &operator=(TempFile &&) = default;

  ~TempFile() { remove(path_.c_str()); }

  // Gets the path to the temporary file.
  absl::string_view GetPath() const { return path_; }

 private:
  explicit TempFile(absl::string_view path) : path_(path) {}

  std::string path_;
};

// An RAII temporary directory that is recursively deleted.
class TempDirectory {
 public:
  // Create a new temporary directory using the given path template string (the
  // same form used by `mkdtemp`). The file will automatically be deleted when
  // the object goes out of scope.
  static std::unique_ptr<TempDirectory> Create(
      absl::string_view path_template) {
    absl::string_view tmp_dir;
    if (const char *env_value = getenv("TMPDIR")) {
      tmp_dir = env_value;
    } else {
      tmp_dir = "/tmp";
    }
    std::string path = absl::StrCat(tmp_dir, "/", path_template);
    if (mkdtemp(const_cast<char *>(path.c_str())) == nullptr) {
      std::cerr << "Failed to create temporary directory '" << path
                << "': " << strerror(errno) << std::endl;
      return nullptr;
    }
    return std::unique_ptr<TempDirectory>(new TempDirectory(path));
  }

  // Explicitly make TempDirectory non-copyable and movable.
  TempDirectory(const TempDirectory &) = delete;
  TempDirectory &operator=(const TempDirectory &) = delete;
  TempDirectory(TempDirectory &&) = default;
  TempDirectory &operator=(TempDirectory &&) = default;

  ~TempDirectory() {
    std::error_code ec;
    std::filesystem::remove_all(path_, ec);
  }

  // Gets the path to the temporary directory.
  absl::string_view GetPath() const { return path_; }

 private:
  explicit TempDirectory(absl::string_view path) : path_(path) {}

  std::string path_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TEMP_FILE_H
