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
#include <map>
#include <string>

namespace bazel_rules_swift {
namespace {

// The placeholder string used by Bazel that should be replaced by
// `DEVELOPER_DIR` at runtime.
static const char kBazelXcodeDeveloperDir[] = "__BAZEL_XCODE_DEVELOPER_DIR__";

// The placeholder string used by Bazel that should be replaced by `SDKROOT`
// at runtime.
static const char kBazelXcodeSdkRoot[] = "__BAZEL_XCODE_SDKROOT__";

// Returns the value of the given environment variable, or the empty string if
// it wasn't set.
std::string GetEnvironmentVariable(const char *name) {
  char *env_value = getenv(name);
  if (env_value == nullptr) {
    return "";
  }
  return env_value;
}

}  // namespace

BazelPlaceholderSubstitutions::BazelPlaceholderSubstitutions() {
  // When targeting Apple platforms, replace the magic Bazel placeholders with
  // the path in the corresponding environment variable. These should be set by
  // the build rules; only attempt to retrieve them if they're actually seen in
  // the argument list.
  placeholder_resolvers_ = {
      {kBazelXcodeDeveloperDir, PlaceholderResolver([]() {
         return GetEnvironmentVariable("DEVELOPER_DIR");
       })},
      {kBazelXcodeSdkRoot,
       PlaceholderResolver([]() { return GetEnvironmentVariable("SDKROOT"); })},
  };
}

BazelPlaceholderSubstitutions::BazelPlaceholderSubstitutions(
    const std::string &developer_dir, const std::string &sdk_root) {
  placeholder_resolvers_ = {
      {kBazelXcodeDeveloperDir,
       PlaceholderResolver([=]() { return developer_dir; })},
      {kBazelXcodeSdkRoot, PlaceholderResolver([=]() { return sdk_root; })},
  };
}

bool BazelPlaceholderSubstitutions::Apply(std::string &arg) {
  bool changed = false;

  // Replace placeholders in the string with their actual values.
  for (auto &pair : placeholder_resolvers_) {
    changed |= FindAndReplace(pair.first, pair.second, arg);
  }

  return changed;
}

bool BazelPlaceholderSubstitutions::FindAndReplace(
    const std::string &placeholder,
    BazelPlaceholderSubstitutions::PlaceholderResolver &resolver,
    std::string &str) {
  int start = 0;
  bool changed = false;
  while ((start = str.find(placeholder, start)) != std::string::npos) {
    std::string resolved_value = resolver.get();
    if (resolved_value.empty()) {
      return false;
    }
    changed = true;
    str.replace(start, placeholder.length(), resolved_value);
    start += resolved_value.length();
  }
  return changed;
}

}  // namespace bazel_rules_swift
