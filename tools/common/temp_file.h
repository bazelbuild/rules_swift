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

#include <cerrno>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

// An RAII temporary file.
class TempFile {
 public:
  // Create a new temporary file using the given path template string (the same
  // form used by `mkstemp`). The file will automatically be deleted when the
  // object goes out of scope.
  static std::unique_ptr<TempFile> Create(const std::string &path_template) {
    size_t size = path_template.size() + 1;
    std::unique_ptr<char[]> path(new char[size]);
    snprintf(path.get(), size, "%s", path_template.c_str());

    if (mkstemp(path.get()) == -1) {
      std::cerr << "Failed to create temporary file: " << strerror(errno)
                << "\n";
      return nullptr;
    }
    return std::unique_ptr<TempFile>(new TempFile(path.get()));
  }

  // Explicitly make TempFile non-copyable and movable.
  TempFile(const TempFile &) = delete;
  TempFile &operator=(const TempFile &) = delete;
  TempFile(TempFile &&) = default;
  TempFile &operator=(TempFile &&) = default;

  ~TempFile() { remove(path_.c_str()); }

  // Gets the path to the temporary file.
  std::string GetPath() const { return path_; }

 private:
  explicit TempFile(const std::string &path) : path_(path) {}

  std::string path_;
};

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TEMP_FILE_H
