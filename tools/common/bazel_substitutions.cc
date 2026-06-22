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

// The placeholder string used by Bazel that should be replaced by the swift
// toolchain root directory. For instance:
// * when using the toolchain within Xcode, this will be something like this:
//   .../Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
// * when using a standalone non-Xcode toolchain, this will be something like:
//   .../swift-6.2-RELEASE.xctoolchain
// Either way, swift binaries are expected to be found at this location under
// usr/bin, swift standard libraries are expected to be found at usr/lib/swift,
// etc...
static const char kBazelSwiftToolchainPath[] = "__BAZEL_SWIFT_TOOLCHAIN_PATH__";

// Returns the value of the given environment variable, or the empty string if
// it wasn't set.
std::string GetAppleEnvironmentVariable(const char* name) {
  char* env_value = getenv(name);
  if (env_value == nullptr) {
    std::cerr
        << "error: required Apple environment variable '" << name
        << "' was not set. Please file an issue on bazelbuild/rules_swift.\n";
    exit(EXIT_FAILURE);
  }
  return env_value;
}

std::string GetToolchainPath() {
  char* toolchain_path = getenv("TOOLCHAIN_PATH");
  if (toolchain_path == nullptr) {
    std::cerr << "error: required Swift toolchain environment variable "
                 "'TOOLCHAIN_PATH' was not set. Please file an issue on "
                 "bazelbuild/rules_swift.\n";
    exit(EXIT_FAILURE);
  }
  return std::string(toolchain_path);
}

}  // namespace

BazelPlaceholderSubstitutions::BazelPlaceholderSubstitutions() {
  // When targeting Apple platforms, replace the magic Bazel placeholders with
  // the path in the corresponding environment variable. These should be set by
  // the build rules; only attempt to retrieve them if they're actually seen in
  // the argument list.
  placeholder_resolvers_ = {
      {kBazelXcodeDeveloperDir, PlaceholderResolver([]() {
         return GetAppleEnvironmentVariable("DEVELOPER_DIR");
       })},
      {kBazelXcodeSdkRoot, PlaceholderResolver([]() {
         return GetAppleEnvironmentVariable("SDKROOT");
       })},
      {kBazelSwiftToolchainPath,
       PlaceholderResolver([]() { return GetToolchainPath(); })}};
}

bool BazelPlaceholderSubstitutions::Apply(std::string& arg) {
  bool changed = false;

  // Replace placeholders in the string with their actual values.
  for (auto& pair : placeholder_resolvers_) {
    changed |= FindAndReplace(pair.first, pair.second, arg);
  }

  return changed;
}

bool BazelPlaceholderSubstitutions::FindAndReplace(
    const std::string& placeholder,
    BazelPlaceholderSubstitutions::PlaceholderResolver& resolver,
    std::string& str) {
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
