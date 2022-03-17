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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_BAZEL_SUBSTITUTIONS_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_BAZEL_SUBSTITUTIONS_H_

#include <string>

#include "absl/container/flat_hash_map.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

// Manages the substitution of special Bazel placeholder strings in command line
// arguments that are used to defer the determination of Apple developer and SDK
// paths until execution time.
class BazelPlaceholderSubstitutions {
 public:
  // Initializes the substitutions by looking them up in the process's
  // environment.
  BazelPlaceholderSubstitutions();

  // Initializes the substitutions with the given fixed strings. Intended to be
  // used for testing.
  BazelPlaceholderSubstitutions(absl::string_view developer_dir,
                                absl::string_view sdk_root);

  // Applies any necessary substitutions to `arg` and returns true if this
  // caused the string to change.
  bool Apply(std::string &arg);

  // The placeholder string used by Bazel that should be replaced by
  // `DEVELOPER_DIR` at runtime.
  inline static constexpr absl::string_view kBazelXcodeDeveloperDir =
      "__BAZEL_XCODE_DEVELOPER_DIR__";

  // The placeholder string used by Bazel that should be replaced by `SDKROOT`
  // at runtime.
  inline static constexpr absl::string_view kBazelXcodeSdkRoot =
      "__BAZEL_XCODE_SDKROOT__";

 private:
  // A mapping from Bazel placeholder strings to the values that should be
  // substituted for them.
  absl::flat_hash_map<std::string, std::string> substitutions_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_BAZEL_SUBSTITUTIONS_H_
