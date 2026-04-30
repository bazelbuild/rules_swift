// Copyright 2025 The Bazel Authors. All rights reserved.
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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TARGET_TRIPLE_H
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TARGET_TRIPLE_H

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "absl/strings/str_cat.h"
#include "absl/strings/str_join.h"
#include "absl/strings/str_split.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

// Represents a target triple as used by LLVM/Swift and provides operations to
// query and modify it.
class TargetTriple {
 public:
  // Creates a new target triple from the given components.
  TargetTriple(absl::string_view arch, absl::string_view vendor,
               absl::string_view os, absl::string_view environment)
      : arch_(arch),
        vendor_(vendor),
        os_(os),
        environment_(environment) {}

  // Parses the given target triple string into its component parts.
  static std::optional<TargetTriple> Parse(absl::string_view target_triple) {
    std::vector<absl::string_view> components =
        absl::StrSplit(target_triple, '-');
    if (components.size() < 3) {
      return std::nullopt;
    }
    return TargetTriple(components[0], components[1], components[2],
                        components.size() > 3 ? components[3] : "");
  }

  // Returns the architecture component of the target triple.
  std::string Arch() const { return arch_; }

  // Returns the vendor component of the target triple.
  std::string Vendor() const { return vendor_; }

  // Returns the OS component of the target triple.
  std::string OS() const { return os_; }

  // Returns the environment component of the target triple.
  std::string Environment() const { return environment_; }

  // Returns this target triple as a string.
  std::string TripleString() const {
    std::string result = absl::StrJoin({arch_, vendor_, os_}, "-");
    if (!environment_.empty()) {
      absl::StrAppend(&result, "-", environment_);
    }
    return result;
  }

  // Returns a copy of this target triple with the version number removed from
  // the OS component (if any).
  TargetTriple WithoutOSVersion() const {
    std::pair<absl::string_view, absl::string_view> os_and_version =
    absl::StrSplit(os_, absl::MaxSplits(absl::ByAnyChar("0123456789"), 1));
    return TargetTriple(arch_, vendor_, os_and_version.first, environment_);
  }

  // Returns a copy of this target triple, replacing its architecture with the
  // given value.
  TargetTriple WithArch(absl::string_view arch) const {
    return TargetTriple(arch, vendor_, os_, environment_);
  }

 private:
  std::string arch_;
  std::string vendor_;
  std::string os_;
  std::string environment_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_TARGET_TRIPLE_H
