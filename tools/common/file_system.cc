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

#include <string>

namespace bazel_rules_swift {

bool PathExists(absl::string_view path) {
  struct stat stats;
  std::string null_terminated_path{path};
  return stat(null_terminated_path.c_str(), &stats) == 0;
}

}  // namespace bazel_rules_swift
