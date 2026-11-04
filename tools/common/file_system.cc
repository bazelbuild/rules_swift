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

#include <filesystem>
#include <fstream>
#include <ostream>
#include <string>

namespace bazel_rules_swift {

std::filesystem::path LongPath(const std::filesystem::path& path) {
#if defined(_WIN32)
  std::error_code ec;
  std::filesystem::path absolute = std::filesystem::absolute(path, ec);
  if (ec) {
    return path;
  }
  std::wstring native = absolute.lexically_normal().make_preferred().wstring();
  if (native.compare(0, 4, L"\\\\?\\") != 0) {
    native.insert(0, L"\\\\?\\");
  }
  return std::filesystem::path(native);
#else
  return path;
#endif
}

bool TouchFile(const std::filesystem::path& path, std::ostream* stderr_stream) {
  std::error_code ec;
  if (!path.parent_path().empty()) {
    std::filesystem::create_directories(LongPath(path.parent_path()), ec);
    if (ec) {
      (*stderr_stream) << "swift_worker: Could not create directory "
                       << path.parent_path() << " (" << ec.message() << ")\n";
      return false;
    }
  }

  std::ofstream stream(LongPath(path));
  if (!stream) {
    (*stderr_stream) << "swift_worker: Could not create " << path << "\n";
    return false;
  }
  return true;
}

bool PathExists(absl::string_view path) {
  struct stat stats;
  std::string null_terminated_path{path};
  return stat(null_terminated_path.c_str(), &stats) == 0;
}

}  // namespace bazel_rules_swift
