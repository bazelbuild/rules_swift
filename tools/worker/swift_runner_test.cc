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

#include "tools/worker/swift_runner.h"

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "gmock/gmock.h"
#include "gtest/gtest.h"
#include "tools/common/xcode_symlink_test_fixture.h"
#include "tools/worker/hermetic_symlink.h"

namespace bazel_rules_swift {
namespace {

using ::testing::Contains;
using ::testing::ElementsAre;
using ::testing::ElementsAreArray;
using ::testing::Pair;
using SwiftRunnerTest = XcodeSymlinkTest;

TEST_F(SwiftRunnerTest,
       CanonicalizesSymlinkedDeveloperDirAndSdkRootInEnvAndArgs) {
  SwiftRunner runner(
      {
          "swiftc",
          "-Xwrapped-swift=-file-prefix-pwd-is-dot",
          "__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains",
          "-sdk",
          "__BAZEL_XCODE_SDKROOT__",
      },
      "");

  EXPECT_THAT(runner.GetJobEnv(),
              Contains(Pair("DEVELOPER_DIR", canonical_developer_dir_)));
  EXPECT_THAT(runner.GetJobEnv(),
              Contains(Pair("SDKROOT", canonical_sdk_root_)));
  EXPECT_THAT(runner.GetArgs(),
              ElementsAre("-file-prefix-map",
                          std::filesystem::current_path().string() + "=.",
                          canonical_developer_dir_ + "/Toolchains", "-sdk",
                          canonical_sdk_root_));

  EXPECT_EQ(std::filesystem::read_symlink(DeveloperDirSymlinkName()).string(),
            canonical_developer_dir_);
}

TEST_F(SwiftRunnerTest, WorkingDirectoryMapsDoNotEnableXcodeRemapping) {
  for (const std::string kind : {"file", "debug", "coverage"}) {
    SCOPED_TRACE(kind);
    SwiftRunner runner(
        {"swiftc", "-Xwrapped-swift=-" + kind + "-prefix-pwd-is-dot"}, "");
    EXPECT_THAT(runner.GetArgs(),
                ElementsAre("-" + kind + "-prefix-map",
                            std::filesystem::current_path().string() + "=."));
  }
}

TEST_F(SwiftRunnerTest, ReusesExistingDeveloperSymlinkWithEquivalentTarget) {
  ASSERT_TRUE(EnsureDeveloperDirSymlink(symlink_developer_dir_));
  ASSERT_TRUE(EnsureDeveloperDirSymlink(canonical_developer_dir_));

  SwiftRunner runner({"swiftc"}, "");
  EXPECT_THAT(runner.GetJobEnv(),
              Contains(Pair("DEVELOPER_DIR", canonical_developer_dir_)));
  EXPECT_EQ(std::filesystem::read_symlink(DeveloperDirSymlinkName()).string(),
            symlink_developer_dir_);
}

TEST_F(SwiftRunnerTest, ReusesEquivalentRelativeSymlinkTarget) {
  const auto link = std::filesystem::current_path() / "nested/developer";
  ASSERT_TRUE(std::filesystem::create_directory(link.parent_path()));
  const auto relative_target = std::filesystem::path(symlink_developer_dir_)
                                   .lexically_relative(link.parent_path());
  std::filesystem::create_directory_symlink(relative_target, link);

  EXPECT_TRUE(EnsureDirectorySymlink(link, canonical_developer_dir_));
  const auto relative_canonical_target =
      std::filesystem::path(canonical_developer_dir_)
          .lexically_relative(link.parent_path());
  EXPECT_TRUE(EnsureDirectorySymlink(link, relative_canonical_target));
  EXPECT_EQ(std::filesystem::read_symlink(link), relative_target);
}

TEST_F(SwiftRunnerTest, RejectsDifferentOrDanglingDeveloperSymlinkTargets) {
  for (const auto& target : {std::filesystem::path(canonical_sdk_root_),
                             std::filesystem::current_path() / "missing"}) {
    SCOPED_TRACE(target.string());
    const auto link = std::filesystem::current_path() /
                      (target.filename().string() + "-link");
    std::filesystem::create_directory_symlink(target, link);
    EXPECT_FALSE(EnsureDirectorySymlink(link, canonical_developer_dir_));
    EXPECT_EQ(std::filesystem::read_symlink(link), target);
  }
}

TEST_F(SwiftRunnerTest, RejectsExistingDirectoryInsteadOfSymlink) {
  const auto directory = std::filesystem::current_path() / "existing";
  ASSERT_TRUE(std::filesystem::create_directory(directory));
  EXPECT_FALSE(EnsureDirectorySymlink(directory, directory));
  EXPECT_TRUE(std::filesystem::is_directory(directory));
  EXPECT_FALSE(std::filesystem::is_symlink(directory));
}

TEST_F(SwiftRunnerTest, CanonicalCoverageMapDoesNotEnableXcodeRemapping) {
  std::ofstream("BUILD.bazel") << "# Test workspace\n";
  SwiftRunner runner(
      {"swiftc", "-Xwrapped-swift=-coverage-prefix-pwd-is-canonical"}, "");
  const std::string cwd = std::filesystem::current_path().string();
  EXPECT_THAT(runner.GetArgs(),
              ElementsAre("-coverage-prefix-map", cwd + "=" + cwd));
}

TEST_F(SwiftRunnerTest, CanonicalDeveloperDirDoesNotDuplicateXcodeMaps) {
  SetEnvironment("DEVELOPER_DIR", canonical_developer_dir_.c_str());
  SetEnvironment("SDKROOT", canonical_sdk_root_.c_str());

  for (const std::string kind : {"file", "debug", "coverage"}) {
    SCOPED_TRACE(kind);
    const std::string flag = "-" + kind + "-prefix-map";
    SwiftRunner runner(
        {"swiftc", flag,
         "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR"},
        "");
    EXPECT_THAT(runner.GetArgs(),
                ElementsAre(flag, canonical_developer_dir_ +
                                      "=/PLACEHOLDER_DEVELOPER_DIR"));
  }
}

TEST_F(SwiftRunnerTest, ExplicitXcodeMapsDoNotRequireWorkingDirectoryMaps) {
  for (const std::string kind : {"file", "debug", "coverage"}) {
    SCOPED_TRACE(kind);
    const std::string flag = "-" + kind + "-prefix-map";
    SwiftRunner runner(
        {"swiftc", flag,
         "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR"},
        "");
    const std::vector<std::string> expected_args = {
        flag,
        canonical_developer_dir_ + "=/PLACEHOLDER_DEVELOPER_DIR",
#if __APPLE__
        flag,
        symlink_developer_dir_ + "=/PLACEHOLDER_DEVELOPER_DIR",
#endif
    };
    EXPECT_THAT(runner.GetArgs(), ElementsAreArray(expected_args));
  }
}

TEST_F(SwiftRunnerTest, ExplicitXcodeMapsCoverBothPathSpellings) {
  for (const std::string kind : {"file", "debug", "coverage"}) {
    for (bool response_file : {false, true}) {
      SCOPED_TRACE(kind + (response_file ? " response file" : " command line"));
      const std::string flag = "-" + kind + "-prefix-map";
      std::vector<std::string> args = {
          "swiftc", "-Xwrapped-swift=-" + kind + "-prefix-pwd-is-dot",
          flag,     "__BAZEL_XCODE_DEVELOPER_DIR__=/PLACEHOLDER_DEVELOPER_DIR",
          flag,     "/other=/source",
      };
      if (response_file) {
        std::ofstream params("compile.params");
        for (size_t i = 1; i < args.size(); ++i) {
          params << args[i] << '\n';
        }
        args = {"swiftc", "@compile.params"};
      }
      SwiftRunner runner(args, "");
      const std::vector<std::string> expected_args = {
          flag, std::filesystem::current_path().string() + "=.",
          flag, canonical_developer_dir_ + "=/PLACEHOLDER_DEVELOPER_DIR",
#if __APPLE__
          flag, symlink_developer_dir_ + "=/PLACEHOLDER_DEVELOPER_DIR",
#endif
          flag, "/other=/source",
      };
      EXPECT_THAT(runner.GetArgs(), ElementsAreArray(expected_args));
    }
  }
}

}  // namespace
}  // namespace bazel_rules_swift
