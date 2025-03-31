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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_FILE_SYSTEM_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_FILE_SYSTEM_H_

#include <string>

#include "absl/status/status.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

// Gets the path to the current working directory.
std::string GetCurrentDirectory();

// Copies the file at src to dest. Returns true if successful.
absl::Status CopyFile(absl::string_view src, absl::string_view dest);

// Creates a directory at the given path, along with any parent directories that
// don't already exist. Returns true if successful.
absl::Status MakeDirs(absl::string_view path, int mode);

// Returns true if the given path exists.
bool PathExists(absl::string_view path);

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_FILE_SYSTEM_H_
