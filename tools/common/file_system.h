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

// Gets the path to the current working directory.
std::string GetCurrentDirectory();

// Returns true if something exists at path.
bool FileExists(const std::string &path);

// Removes the file at path. Returns true if successful.
bool RemoveFile(const std::string &path);

// Copies the file at src to dest. Returns true if successful.
bool CopyFile(const std::string &src, const std::string &dest);

// Creates a directory at the given path, along with any parent directories that
// don't already exist. Returns true if successful.
bool MakeDirs(const std::string &path, int mode);

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_FILE_SYSTEM_H_
