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

#include "tools/common/path_utils.h"

#include <cstring>
#include <string>

const char *Basename(const char *path) {
  const char *base = strrchr(path, '/');
  return base ? (base + 1) : path;
}

std::string Dirname(const std::string &path) {
  auto last_slash = path.rfind('/');
  if (last_slash == std::string::npos) {
    return std::string();
  }
  return path.substr(0, last_slash);
}

std::string ReplaceExtension(const std::string &path,
                             const std::string &new_extension) {
  auto last_dot = path.rfind('.');
  auto last_slash = path.rfind('/');

  // If there was no dot, or if it was part of a previous path segment, append
  // the extension to the path.
  if (last_dot == std::string::npos || last_dot < last_slash) {
    return path + new_extension;
  }
  return path.substr(0, last_dot) + new_extension;
}
