// Copyright 2026 The Bazel Authors. All rights reserved.
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

#include <filesystem>
#include <string>

#include "gtest/gtest.h"
#include "tools/common/xcode_symlink_test_fixture.h"

namespace bazel_rules_swift {
namespace {

using BazelPlaceholderSubstitutionsTest = XcodeSymlinkTest;

TEST_F(BazelPlaceholderSubstitutionsTest,
       ResolvesSymlinkedDeveloperDirAndSdkRoot) {
  BazelPlaceholderSubstitutions substitutions;

  std::string dev_arg = "__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains";
  EXPECT_TRUE(substitutions.Apply(dev_arg));
  EXPECT_EQ(dev_arg, canonical_developer_dir_ + "/Toolchains");

  std::string sdk_arg = "__BAZEL_XCODE_SDKROOT__/System/Library";
  EXPECT_TRUE(substitutions.Apply(sdk_arg));
  EXPECT_EQ(sdk_arg, canonical_sdk_root_ + "/System/Library");
}

TEST_F(BazelPlaceholderSubstitutionsTest, PreservesNonexistentPaths) {
  const std::string developer_dir = symlink_developer_dir_ + "/missing";
  const std::string sdk_root = symlink_sdk_root_ + "/missing";
  ASSERT_FALSE(std::filesystem::exists(developer_dir));
  ASSERT_FALSE(std::filesystem::exists(sdk_root));
  SetEnvironment("DEVELOPER_DIR", developer_dir.c_str());
  SetEnvironment("SDKROOT", sdk_root.c_str());
  BazelPlaceholderSubstitutions substitutions;

  std::string dev_arg = "__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains";
  EXPECT_TRUE(substitutions.Apply(dev_arg));
  EXPECT_EQ(dev_arg, developer_dir + "/Toolchains");

  std::string sdk_arg = "__BAZEL_XCODE_SDKROOT__/System/Library";
  EXPECT_TRUE(substitutions.Apply(sdk_arg));
  EXPECT_EQ(sdk_arg, sdk_root + "/System/Library");
}

}  // namespace
}  // namespace bazel_rules_swift
