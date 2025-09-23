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
#include "tools/common/process.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <sstream>

#include "absl/container/flat_hash_map.h"
#include "absl/strings/str_replace.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {
namespace {

// Returns the value of the given environment variable, or the empty string if
// it wasn't set.
std::string GetEnvironmentVariable(absl::string_view name) {
  std::string null_terminated_name(name.data(), name.length());
  char *env_value = getenv(null_terminated_name.c_str());
  if (env_value == nullptr) {
    std::cerr << "error: required Apple environment variable '" << name << "' was not set. Please file an issue on bazelbuild/rules_swift.\n";
    exit(EXIT_FAILURE);
  }
  return env_value;
}

std::string GetToolchainPath() {
#if !defined(__APPLE__)
  return "";
#endif

  char *toolchain_id = getenv("TOOLCHAINS");
  std::ostringstream stdout_stream;
  std::ostream stderr_stream(nullptr);
  int exit_code =
      RunSubProcess({"/usr/bin/xcrun", "--find", "clang"},
                    /*env=*/nullptr, stdout_stream, stderr_stream);
  if (exit_code != 0) {
    std::cerr << stdout_stream.str() << "Error: `TOOLCHAINS=" << toolchain_id
              << "xcrun --find clang` failed with error code " << exit_code
              << std::endl;
    exit(EXIT_FAILURE);
  }

  if (stdout_stream.str().empty()) {
    std::cerr << "Error: TOOLCHAINS was set to '" << toolchain_id
              << "' but no toolchain with that ID was found" << std::endl;
    exit(EXIT_FAILURE);
  } else if ((toolchain_id != nullptr)
             && stdout_stream.str().find("XcodeDefault.xctoolchain") != std::string::npos) {
    // NOTE: Ideally xcrun would fail if the toolchain we asked for didn't exist
    // but it falls back to the DEVELOPER_DIR instead, so we have to check the
    // output ourselves.
    std::cerr << "Error: TOOLCHAINS was set to '" << toolchain_id
              << "' but the default toolchain was found, that likely means a "
                 "matching "
              << "toolchain isn't installed" << std::endl;
    exit(EXIT_FAILURE);
  }

  std::filesystem::path toolchain_path(stdout_stream.str());
  // Remove usr/bin/clang components to get the root of the custom toolchain
  return toolchain_path.parent_path().parent_path().parent_path().string();
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
  if (std::string toolchain_path = GetToolchainPath();
      !toolchain_path.empty()) {
    substitutions_[kBazelSwiftToolchainPath] = toolchain_path;
  }
}

bool BazelPlaceholderSubstitutions::Apply(std::string &arg) {
  return absl::StrReplaceAll(substitutions_, &arg) > 0;
}

}  // namespace bazel_rules_swift
