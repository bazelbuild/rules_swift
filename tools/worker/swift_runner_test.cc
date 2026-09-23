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

#include <fstream>
#include <memory>
#include <string>

#include "testing/base/public/gmock.h"
#include "testing/base/public/gunit.h"
#include "absl/container/flat_hash_map.h"
#include "absl/strings/str_cat.h"
#include "tools/common/file_system.h"
#include "tools/common/temp_file.h"

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
  EXPECT_THAT(runner.GetMacroExpansionDir(), Eq("some/relative/path"));
}

TEST(SwiftRunnerTest, JobEnvTmpdirWithMacroExpansionDir) {
  SwiftRunner runner(
      {"swiftc", "-Xwrapped-swift=-macro-expansion-dir=foo"},
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(runner.GetJobEnv(), Contains(Pair("TMPDIR", "/execroot/foo")));
  EXPECT_THAT(runner.GetMacroExpansionDir(), Eq("foo"));
}

TEST(SwiftRunnerTest, JobEnvTmpdirWithoutMacroExpansionDir) {
  SwiftRunner runner(
      {"swiftc", "main.swift"},
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(runner.GetJobEnv(), Contains(Pair("TMPDIR", "/execroot/_tmp")));
  EXPECT_THAT(runner.GetMacroExpansionDir(), Eq(""));
}

TEST(SwiftRunnerTest, JobEnvTmpdirOverridesHostTmpdirWhenMacroExpansionDirOmitted) {
  absl::flat_hash_map<std::string, std::string> env = {
      {"TMPDIR", "/var/folders/host_tmp"}};
  SwiftRunner runner(
      {"swiftc", "main.swift"},
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/env);
  EXPECT_THAT(runner.GetJobEnv(), Contains(Pair("TMPDIR", "/execroot/_tmp")));
}

TEST(SwiftRunnerTest, RemapMacroExpansionPathsReplacesCwdWithDot) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("macro_expansion_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string sub_dir = absl::StrCat(temp_dir->GetPath(), "/sub/dir");
  ASSERT_TRUE(MakeDirs(sub_dir, S_IRWXU).ok());

  std::string file1_path = absl::StrCat(temp_dir->GetPath(), "/file1.swift");
  std::string file1_content =
      "// original-source-range: /execroot/bazel-out/foo/bar.swift:1:2\n";
  {
    std::ofstream f(file1_path);
    f << file1_content;
  }

  std::string file2_path = absl::StrCat(sub_dir, "/file2.swift");
  std::string file2_content =
      "// original-source-range: some/relative/path.swift:10:20\n";
  {
    std::ofstream f(file2_path);
    f << file2_content;
  }

  std::string file3_path = absl::StrCat(sub_dir, "/file3.swift");
  std::string file3_content = "prefix /execroot/a middle /execroot/b suffix\n";
  {
    std::ofstream f(file3_path);
    f << file3_content;
  }

  SwiftRunner runner(
      {"swiftc", absl::StrCat("-Xwrapped-swift=-macro-expansion-dir=",
                              temp_dir->GetPath())},
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());

  runner.RemapMacroExpansionPaths();

  auto ReadFile = [](const std::string& path) {
    std::ifstream f(path);
    return std::string((std::istreambuf_iterator<char>(f)),
                       std::istreambuf_iterator<char>());
  };

  EXPECT_EQ(ReadFile(file1_path),
            "// original-source-range: ./bazel-out/foo/bar.swift:1:2\n");
  EXPECT_EQ(ReadFile(file2_path), file2_content);
  EXPECT_EQ(ReadFile(file3_path), "prefix ./a middle ./b suffix\n");
}

TEST(CompilationPlanTest, ModuleJobs) {
  std::string driver_output =
      "swift-frontend -emit-module -o MyModule.swiftmodule MyModule.swift\n"
      "swift-frontend -c -o MyModule.o MyModule.swift\n";
  CompilationPlan plan(driver_output);
  EXPECT_THAT(plan.ModuleJobs(),
              ElementsAre("swift-frontend -emit-module -o MyModule.swiftmodule "
                          "MyModule.swift"));
}

TEST(CompilationPlanTest, CodegenJobsEmptyReturnsAll) {
  std::string driver_output =
      "swift-frontend -emit-module -o MyModule.swiftmodule MyModule.swift\n"
      "swift-frontend -c -o MyModule.o MyModule.swift\n";
  CompilationPlan plan(driver_output);
  EXPECT_THAT(plan.CodegenJobsForOutputs({}),
              ElementsAre("swift-frontend -c -o MyModule.o MyModule.swift"));
}

TEST(CompilationPlanTest, CodegenJobsForOutputs_ExactMatch) {
  std::string driver_output =
      "swift-frontend -c -o path/to/a.o a.swift\n"
      "swift-frontend -c -o path/to/b.o b.swift\n";
  CompilationPlan plan(driver_output);
  EXPECT_THAT(plan.CodegenJobsForOutputs({"path/to/a.o"}),
              ElementsAre("swift-frontend -c -o path/to/a.o a.swift"));
}

TEST(CompilationPlanTest, CodegenJobsForOutputs_DirectoryMatch) {
  std::string driver_output =
      "swift-frontend -c -o path/to/dir.o/a.o a.swift\n"
      "swift-frontend -c -o path/to/dir.o/b.o b.swift\n"
      "swift-frontend -c -o path/to/other.o other.swift\n";
  CompilationPlan plan(driver_output);
  EXPECT_THAT(
      plan.CodegenJobsForOutputs({"path/to/dir.o"}),
      UnorderedElementsAre("swift-frontend -c -o path/to/dir.o/a.o a.swift",
                           "swift-frontend -c -o path/to/dir.o/b.o b.swift"));
}

TEST(CompilationPlanTest, CodegenJobsForOutputs_DirectoryMatchTrailingSlash) {
  std::string driver_output =
      "swift-frontend -c -o path/to/dir.o/a.o a.swift\n";
  CompilationPlan plan(driver_output);
  EXPECT_THAT(plan.CodegenJobsForOutputs({"path/to/dir.o/"}),
              ElementsAre("swift-frontend -c -o path/to/dir.o/a.o a.swift"));
}

TEST(CompilationPlanTest, CodegenJobsForOutputs_DirectorySubstringProtection) {
  std::string driver_output =
      "swift-frontend -c -o path/to/dir.o/a.o a.swift\n"
      "swift-frontend -c -o path/to/dir.o_other/b.o b.swift\n"
      "swift-frontend -c -o path/to_dir.o/c.o c.swift\n";
  CompilationPlan plan(driver_output);

  EXPECT_THAT(plan.CodegenJobsForOutputs({"dir.o"}),
              ElementsAre("swift-frontend -c -o path/to/dir.o/a.o a.swift"));
}

}  // namespace
}  // namespace bazel_rules_swift
