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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_XCODE_SYMLINK_TEST_FIXTURE_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_XCODE_SYMLINK_TEST_FIXTURE_H_

#include <cstdlib>
#include <filesystem>
#include <map>
#include <memory>
#include <optional>
#include <string>

#include "gtest/gtest.h"
#include "tools/common/temp_file.h"

namespace bazel_rules_swift {

class XcodeSymlinkTest : public testing::Test {
 protected:
  void SetUp() override {
    original_directory_ = std::filesystem::current_path();
    for (const char* name : {"DEVELOPER_DIR", "SDKROOT"}) {
      const char* value = std::getenv(name);
      original_environment_[name] =
          value ? std::optional<std::string>(value) : std::nullopt;
    }

    temp_dir_ = TempDirectory::Create("xcode_symlink_test.XXXXXX");
    ASSERT_NE(temp_dir_, nullptr);
    auto root = std::filesystem::canonical(temp_dir_->GetPath());
    auto xcode = root / "Xcode_27.1.0.app";
    auto developer = xcode / "Contents/Developer";
    auto sdk = developer / "Platforms/MacOSX.platform/MacOSX.sdk";
    ASSERT_TRUE(std::filesystem::create_directories(sdk));
    auto alias = root / "Xcode_27.1.0.27A9275.app";
    std::error_code ec;
    std::filesystem::create_directory_symlink(xcode, alias, ec);
#if defined(_WIN32)
    if (ec == std::errc::operation_not_permitted ||
        ec == std::errc::permission_denied) {
      GTEST_SKIP() << "Creating symlinks requires Windows developer mode: "
                   << ec;
    }
#endif
    ASSERT_FALSE(ec) << ec.message();

    canonical_developer_dir_ = std::filesystem::canonical(developer).string();
    canonical_sdk_root_ = std::filesystem::canonical(sdk).string();
    symlink_developer_dir_ = (alias / "Contents/Developer").string();
    symlink_sdk_root_ =
        (alias / "Contents/Developer/Platforms/MacOSX.platform/MacOSX.sdk")
            .string();
    SetEnvironment("DEVELOPER_DIR", symlink_developer_dir_.c_str());
    SetEnvironment("SDKROOT", symlink_sdk_root_.c_str());
    std::filesystem::current_path(root);
  }

  void TearDown() override {
    std::filesystem::current_path(original_directory_);
    for (const auto& [name, value] : original_environment_) {
      SetEnvironment(name.c_str(), value ? value->c_str() : nullptr);
    }
  }

  static void SetEnvironment(const char* name, const char* value) {
#if defined(_WIN32)
    ASSERT_EQ(_putenv_s(name, value ? value : ""), 0);
#else
    ASSERT_EQ(value ? setenv(name, value, 1) : unsetenv(name), 0);
#endif
  }

  std::string canonical_developer_dir_;
  std::string canonical_sdk_root_;
  std::string symlink_developer_dir_;
  std::string symlink_sdk_root_;

 private:
  std::filesystem::path original_directory_;
  std::map<std::string, std::optional<std::string>> original_environment_;
  std::unique_ptr<TempDirectory> temp_dir_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_XCODE_SYMLINK_TEST_FIXTURE_H_
