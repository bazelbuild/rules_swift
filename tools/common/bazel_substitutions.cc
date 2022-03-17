// Copyright 2021 The Bazel Authors. All rights reserved.
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

#include "tools/common/bazel_substitutions.h"

#include <cstdlib>
#include <iostream>
#include <string>

#include "absl/container/flat_hash_map.h"
#include "absl/strings/str_replace.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {
namespace {

// Returns the value of the given environment variable, or the empty string if
// it wasn't set.
std::string GetEnvironmentVariable(absl::string_view name) {
  char *env_value = getenv(name.data());
  if (env_value == nullptr) {
    return "";
  }
  return env_value;
}

}  // namespace

BazelPlaceholderSubstitutions::BazelPlaceholderSubstitutions() {
  // When targeting Apple platforms, replace the magic Bazel placeholders with
  // the path in the corresponding environment variable, which should be set by
  // the build rules. If the variable isn't set, we don't store a substitution;
  // if it was needed then the eventual replacement will be a no-op and the
  // command will presumably fail later.
  if (std::string developer_dir = GetEnvironmentVariable("DEVELOPER_DIR");
      !developer_dir.empty()) {
    substitutions_[kBazelXcodeDeveloperDir] = developer_dir;
  }
  if (std::string sdk_root = GetEnvironmentVariable("SDKROOT");
      !sdk_root.empty()) {
    substitutions_[kBazelXcodeSdkRoot] = sdk_root;
  }
}

BazelPlaceholderSubstitutions::BazelPlaceholderSubstitutions(
    absl::string_view developer_dir, absl::string_view sdk_root) {
  substitutions_[kBazelXcodeDeveloperDir] = std::string(developer_dir);
  substitutions_[kBazelXcodeSdkRoot] = std::string(sdk_root);
}

bool BazelPlaceholderSubstitutions::Apply(std::string &arg) {
  return absl::StrReplaceAll(substitutions_, &arg) > 0;
}

}  // namespace bazel_rules_swift
