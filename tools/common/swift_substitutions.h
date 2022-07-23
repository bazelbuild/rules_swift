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

#ifndef THIRD_PARTY_BAZEL_RULES_RULES_SWIFT_TOOLS_COMMON_SWIFT_SUBSTITUTIONS_H_
#define THIRD_PARTY_BAZEL_RULES_RULES_SWIFT_TOOLS_COMMON_SWIFT_SUBSTITUTIONS_H_

#include "absl/container/flat_hash_map.h"
#include "absl/strings/string_view.h"
#include "tools/common/bazel_substitutions.h"

namespace bazel_rules_swift {

// Manages the substitution of special Swift placeholder strings in command line
// arguments that are used to defer the determination of toolchain and platform
// paths until execution time.
class SwiftPlaceholderSubstitutions {
 public:
  SwiftPlaceholderSubstitutions();

  // Applies any necessary substitutions to `arg` and returns true if this
  // caused the string to change.
  bool Apply(std::string &arg);

  inline static constexpr absl::string_view kSwiftToolchainDir =
      "__SWIFT_TOOLCHAIN_DIR__";
  inline static constexpr absl::string_view kSwiftPlatformDir =
      "__SWIFT_PLATFORM_DIR__";

 private:
  // A mapping from bazel substitutes to their values.
  BazelPlaceholderSubstitutions bazel_substitutions_;

  // A mapping from swift toolchain to their substituted values.
  absl::flat_hash_map<std::string, std::string> substitutions_;
};

}  // namespace bazel_rules_swift

#endif  // THIRD_PARTY_BAZEL_RULES_RULES_SWIFT_TOOLS_COMMON_SWIFT_SUBSTITUTIONS_H_
