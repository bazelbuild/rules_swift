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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_PATH_UTILS_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_PATH_UTILS_H_

#include <string>

#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

// Returns the base name of the given filepath. For example, given
// "/foo/bar/baz.txt", returns "baz.txt".
absl::string_view Basename(absl::string_view path);

// Returns the directory name of the given filepath. For example, given
// "/foo/bar/baz.txt", returns "/foo/bar".
absl::string_view Dirname(absl::string_view path);

// Returns the extension of the file specified by `path`. If the file has no
// extension, the empty string is returned.
absl::string_view GetExtension(absl::string_view path,
                               bool all_extensions = false);

// Replaces the file extension of path with new_extension. It is assumed that
// new_extension starts with a dot if it is desired for a dot to precede the new
// extension in the returned path. If the path does not have a file extension,
// then new_extension is appended to it.
std::string ReplaceExtension(absl::string_view path,
                             absl::string_view new_extension,
                             bool all_extensions = false);

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_PATH_UTILS_H_
