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

#include "tools/common/swift_substitutions.h"

#include "absl/strings/str_replace.h"
#include "absl/strings/substitute.h"
#include "absl/types/optional.h"

namespace bazel_rules_swift {
namespace {
// Returns the value of the given environment variable, or nullopt if it wasn't
// set.
absl::optional<std::string> GetEnvironmentVariable(absl::string_view name) {
  std::string null_terminated_name(name.data(), name.length());
  char* env_value = getenv(null_terminated_name.c_str());
  if (env_value == nullptr) {
    return absl::nullopt;
  }
  return env_value;
}

}  // namespace

SwiftPlaceholderSubstitutions::SwiftPlaceholderSubstitutions() {
  if (absl::optional<std::string> swift_toolchain_override =
          GetEnvironmentVariable("SWIFT_TOOLCHAIN_OVERRIDE");
      swift_toolchain_override.has_value()) {
    substitutions_[kSwiftToolchainDir] = *swift_toolchain_override;
  } else {
    substitutions_[kSwiftToolchainDir] =
        "__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains/XcodeDefault.xctoolchain";
  }

  if (absl::optional<std::string> swift_platform_override =
          GetEnvironmentVariable("SWIFT_PLATFORM_OVERRIDE");
      swift_platform_override.has_value()) {
    substitutions_[kSwiftPlatformDir] = *swift_platform_override;
  } else if (absl::optional<std::string> apple_sdk_platform =
                 GetEnvironmentVariable("APPLE_SDK_PLATFORM");
             apple_sdk_platform.has_value()) {
    substitutions_[kSwiftPlatformDir] =
        absl::Substitute("__BAZEL_XCODE_DEVELOPER_DIR__/Platforms/$0.platform",
                         *apple_sdk_platform);
  }
}

bool SwiftPlaceholderSubstitutions::Apply(std::string& arg) {
  // Order here matters. Swift substitutions must be applied first.
  // They can produce bazel substitutions that require further substitution.
  bool swift_changed = absl::StrReplaceAll(substitutions_, &arg) > 0;
  return bazel_substitutions_.Apply(arg) > 0 || swift_changed;
}
}  // namespace bazel_rules_swift
