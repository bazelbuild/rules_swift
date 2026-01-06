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

#include <string>

#include "testing/base/public/gmock.h"
#include "testing/base/public/gunit.h"
#include "absl/container/flat_hash_map.h"

namespace bazel_rules_swift {
namespace {

using ::testing::Contains;
using ::testing::ElementsAre;
using ::testing::Eq;
using ::testing::Pair;
using ::testing::UnorderedElementsAre;

std::string GetCurrentDirectoryForTest() { return "/execroot"; }

absl::flat_hash_map<std::string, std::string> GetJobEnvForTest() {
  return {{"DEVELOPER_DIR", "/developer"}, {"SDKROOT", "/sdk"}};
}

TEST(SwiftRunnerTest, ToolArgs) {
  SwiftRunner runner({"swiftc", "main.swift"});
  EXPECT_THAT(runner.GetToolArgs(), ElementsAre(
#if __APPLE__
                                        "/usr/bin/xcrun",
#endif
                                        "swiftc"));
}

TEST(SwiftRunnerTest, ArgsProcessingToolsDirectory) {
  SwiftRunner runner({"swiftc", "-tools-directory", "some/relative/path"},
                     /*force_response_file=*/false,
                     /*get_current_directory=*/GetCurrentDirectoryForTest);
  EXPECT_THAT(runner.GetArgs(),
              ElementsAre("-tools-directory", "/execroot/some/relative/path"));
}

TEST(SwiftRunnerTest, ArgsProcessingTarget) {
  SwiftRunner runner({"swiftc", "-target", "arm64-apple-macos26.0"});
  EXPECT_THAT(runner.GetTargetTriple(), Eq("arm64-apple-macos26.0"));
}

TEST(SwiftRunnerTest, ArgsProcessingModuleName) {
  SwiftRunner runner({"swiftc", "-module-name", "MyModule"});
  EXPECT_THAT(runner.GetModuleName(), Eq("MyModule"));
}

TEST(SwiftRunnerTest, ArgsProcessingModuleAlias) {
  SwiftRunner runner({"swiftc", "-module-alias", "source=alias",
                      "-module-alias", "other_source=other_alias"});
  EXPECT_THAT(runner.GetAliasToSourceMapping(),
              UnorderedElementsAre(Pair("alias", "source"),
                                   Pair("other_alias", "other_source")));
}

TEST(SwiftRunnerTest, ArgsProcessingBazelTargetLabel) {
  SwiftRunner runner(
      {"swiftc", "-Xwrapped-swift=-bazel-target-label=//some:target"});
  EXPECT_THAT(runner.GetTargetLabel(), Eq("//some:target"));
}

TEST(SwiftRunnerTest, ArgsProcessingDebugPrefixPwdIsDot) {
  SwiftRunner runner({"swiftc", "-Xwrapped-swift=-debug-prefix-pwd-is-dot"},
                     /*force_response_file=*/false,
                     /*get_current_directory=*/GetCurrentDirectoryForTest,
                     /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(runner.GetArgs(),
              ElementsAre("-debug-prefix-map", "/execroot=."
#if __APPLE__
                          ,
                          "-debug-prefix-map", "/developer=/DEVELOPER_DIR"
#endif
                          ));
}

TEST(SwiftRunnerTest, ArgsProcessingFilePrefixPwdIsDot) {
  SwiftRunner runner({"swiftc", "-Xwrapped-swift=-file-prefix-pwd-is-dot"},
                     /*force_response_file=*/false,
                     /*get_current_directory=*/GetCurrentDirectoryForTest,
                     /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(runner.GetArgs(),
              ElementsAre("-file-prefix-map", "/execroot=."
#if __APPLE__
                          ,
                          "-file-prefix-map", "/developer=/DEVELOPER_DIR"
#endif
                          ));
}

TEST(SwiftRunnerTest, ArgsProcessingMacroExpansionDir) {
  SwiftRunner runner(
      {"swiftc", "-Xwrapped-swift=-macro-expansion-dir=some/relative/path"},
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(runner.GetJobEnv(),
              Contains(Pair("TMPDIR", "/execroot/some/relative/path")));
}

}  // namespace
}  // namespace bazel_rules_swift
