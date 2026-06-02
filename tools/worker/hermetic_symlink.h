// Copyright 2026 The Bazel Authors. All rights reserved.
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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_HERMETIC_SYMLINK_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_HERMETIC_SYMLINK_H_

#include <filesystem>
#include <functional>
#include <string>
#include <string_view>

namespace bazel_rules_swift {

// Removes trailing slashes from `developer_dir`, preserving a root path.
std::string NormalizeDeveloperDir(std::string developer_dir);

// Returns the current working directory-relative symlink name for the active
// Xcode version's developer directory, or an empty string if the active Xcode
// version is unavailable.
std::string DeveloperDirSymlinkName();

// Ensures that `link` points to `target`. This is safe under local
// non-sandboxed execution, where concurrent actions can race to create the same
// symlink.
bool EnsureDirectorySymlink(const std::filesystem::path& link,
                            const std::filesystem::path& target);

// Ensures that DeveloperDirSymlinkName() in the current working directory
// points to `developer_dir`. This is safe under local non-sandboxed execution,
// where concurrent actions can race to create the same symlink.
bool EnsureDeveloperDirSymlink(const std::string& developer_dir);

// Ensures that DeveloperDirSymlinkName() in the current working directory
// points to the current DEVELOPER_DIR. This is a no-op if DEVELOPER_DIR is
// unavailable, and exits if the symlink cannot be created.
void EnsureDeveloperDirSymlinkFromEnv();

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_HERMETIC_SYMLINK_H_
