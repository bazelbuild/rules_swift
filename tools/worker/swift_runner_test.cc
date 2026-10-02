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

#include <sys/stat.h>

#include <fstream>
#include <iterator>
#include <memory>
#include <sstream>
#include <string>

#include "testing/base/public/gmock.h"
#include "testing/base/public/gunit.h"
#include "absl/container/flat_hash_map.h"
#include "absl/strings/str_cat.h"
#include "absl/strings/string_view.h"
#include "tools/common/file_system.h"
#include "tools/common/temp_file.h"

namespace bazel_rules_swift {
namespace {

using ::testing::Contains;
using ::testing::ElementsAre;
using ::testing::Eq;
using ::testing::HasSubstr;
using ::testing::Not;
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

TEST(CompilationPlanTest,
     StripsResponseFileExpansionCommentsAndHandlesQuotedAndSilIrOutputs) {
  std::string driver_output =
      "swift-frontend @/tmp/module.resp # -emit-module -o MyMod.swiftmodule\n"
      "swift-frontend @/tmp/codegen1.resp # -c -o 'dir with spaces/a.o' "
      "a.swift\n"
      "swift-frontend -emit-sil -sil-output-path out/b.sil b.swift\n"
      "swift-frontend -emit-ir -ir-output-path out/c.ll c.swift\n";
  CompilationPlan plan(driver_output);
  EXPECT_THAT(plan.ModuleJobs(),
              ElementsAre("swift-frontend @/tmp/module.resp"));
  EXPECT_THAT(plan.CodegenJobsForOutputs({"dir with spaces/a.o"}),
              ElementsAre("swift-frontend @/tmp/codegen1.resp"));
  EXPECT_THAT(
      plan.CodegenJobsForOutputs({"out/b.sil"}),
      ElementsAre(
          "swift-frontend -emit-sil -sil-output-path out/b.sil b.swift"));
  EXPECT_THAT(
      plan.CodegenJobsForOutputs({"out/c.ll"}),
      ElementsAre("swift-frontend -emit-ir -ir-output-path out/c.ll c.swift"));
}

TEST(SwiftRunnerTest, ArgsProcessingAdditionalWrapperFlagsAndPlaceholders) {
  std::string cache_dir_path;
  {
    SwiftRunner runner(
        {
            "swiftc",
            "-Xwrapped-swift=-warning-as-error=diag_one",
            "-Xwrapped-swift=-warning-as-error=diag_two",
            "-Xwrapped-swift=-layering-check-deps-modules=pkg/tgt.deps-modules",
            "-Xwrapped-swift=-generated-header-rewriter=bin/rewriter",
            "-Xwrapped-swift=-tool-arg=generated_header_rewriter=--rewrite-foo",
            "-Xwrapped-swift=-tool-arg=generated_header_rewriter=--rewrite-bar",
            "-Xwrapped-swift=-ephemeral-module-cache",
            "__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains",
            "-sdk",
            "__BAZEL_XCODE_SDKROOT__",
        },
        /*force_response_file=*/false,
        /*get_current_directory=*/GetCurrentDirectoryForTest,
        /*job_env=*/GetJobEnvForTest());

    EXPECT_THAT(runner.GetWarningsAsErrors(),
                UnorderedElementsAre("diag_one", "diag_two"));
    EXPECT_THAT(runner.GetDepsModulesPath(), Eq("pkg/tgt.deps-modules"));
    EXPECT_THAT(runner.GetGeneratedHeaderRewriterPath(), Eq("bin/rewriter"));
    EXPECT_THAT(runner.GetPassthroughToolArgs(),
                UnorderedElementsAre(
                    Pair("generated_header_rewriter",
                         ElementsAre("--rewrite-foo", "--rewrite-bar"))));

    ASSERT_THAT(runner.GetArgs().size(), Eq(5));
    EXPECT_THAT(runner.GetArgs()[0], Eq("-module-cache-path"));
    cache_dir_path = runner.GetArgs()[1];
    EXPECT_TRUE(PathExists(cache_dir_path));
    EXPECT_THAT(runner.GetArgs()[2], Eq("/developer/Toolchains"));
    EXPECT_THAT(runner.GetArgs()[3], Eq("-sdk"));
    EXPECT_THAT(runner.GetArgs()[4], Eq("/sdk"));
  }
  EXPECT_FALSE(PathExists(cache_dir_path));
}

TEST(SwiftRunnerTest, ResponseFileProcessingForcedAndUnforced) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("resp_file_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string forced_resp_path =
      absl::StrCat(temp_dir->GetPath(), "/forced.params");
  {
    std::ofstream out(forced_resp_path);
    out << "\"-module-name\"\n"
        << "\"My\\\"Quoted\\\\Mod\"\n"
        << "\"-tools-directory\"\n"
        << "\"rel/tools\"\n"
        << "\"-Xwrapped-swift=-warning-as-error=forced_diag\"\n"
        << "file\\ with\\ spaces.swift\n";
  }

  SwiftRunner forced_runner(
      {"swiftc", absl::StrCat("@", forced_resp_path)},
      /*force_response_file=*/true,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(forced_runner.GetModuleName(), Eq("My\"Quoted\\Mod"));
  EXPECT_THAT(forced_runner.GetWarningsAsErrors(), ElementsAre("forced_diag"));
  EXPECT_THAT(forced_runner.GetArgs(),
              ElementsAre("-module-name", "My\"Quoted\\Mod", "-tools-directory",
                          "/execroot/rel/tools", "file with spaces.swift"));

  std::string unforced_resp_path =
      absl::StrCat(temp_dir->GetPath(), "/unforced.params");
  {
    std::ofstream out(unforced_resp_path);
    out << "-module-name\n"
        << "UnforcedMod\n"
        << "-tools-directory\n"
        << "rel/tools\n"
        << "-Xwrapped-swift=-bazel-target-label=//pkg:unforced\n"
        << "main.swift\n";
  }

  SwiftRunner unforced_runner(
      {"swiftc", absl::StrCat("@", unforced_resp_path),
       "@/nonexistent/response_file.params"},
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(unforced_runner.GetModuleName(), Eq("UnforcedMod"));
  EXPECT_THAT(unforced_runner.GetTargetLabel(), Eq("//pkg:unforced"));
  EXPECT_THAT(unforced_runner.GetArgs(),
              ElementsAre("-module-name", "UnforcedMod", "-tools-directory",
                          "/execroot/rel/tools", "main.swift",
                          "@/nonexistent/response_file.params"));
}

TEST(SwiftRunnerTest, CompileModuleFromInterfaceDirectAndInferred) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("swiftinterface_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string swiftmodule_dir =
      absl::StrCat(temp_dir->GetPath(), "/Foo.swiftmodule");
  ASSERT_TRUE(MakeDirs(swiftmodule_dir, S_IRWXU).ok());

  std::string arm64e_interface =
      absl::StrCat(swiftmodule_dir, "/arm64e-apple-macos.swiftinterface");
  {
    std::ofstream out(arm64e_interface);
    out << "// swift-interface-format-version: 1.0\n"
        << "// swift-module-flags: -target arm64e-apple-macos13.0 "
           "-enable-library-evolution -O -module-name Foo\n"
        << "import Swift\n";
  }

  // Test arm64 -> arm64e fallback when only arm64e-apple-macos.swiftinterface
  // exists in the .swiftmodule directory, and verify -target from interface
  // flags is stripped.
  SwiftRunner fallback_runner(
      {
          "swiftc",
          "-target",
          "arm64-apple-macos14.0",
          "-compile-module-from-interface",
          absl::StrCat(
              "-Xwrapped-swift=-explicit-compile-module-from-interface=",
              swiftmodule_dir),
      },
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(
      fallback_runner.GetArgs(),
      ElementsAre("-target", "arm64-apple-macos14.0",
                  "-compile-module-from-interface", arm64e_interface,
                  "-enable-library-evolution", "-O", "-module-name", "Foo"));

  // Now create arm64-apple-macos.swiftinterface and verify exact arch match is
  // preferred over arm64e fallback, and also test direct .swiftinterface path.
  std::string arm64_interface =
      absl::StrCat(swiftmodule_dir, "/arm64-apple-macos.swiftinterface");
  {
    std::ofstream out(arm64_interface);
    out << "// swift-interface-format-version: 1.0\n"
        << "// swift-module-flags: -target x86_64-apple-macos12.0 "
           "-enable-library-evolution -module-name FooExact\n";
  }

  SwiftRunner exact_runner(
      {
          "swiftc",
          "-target",
          "arm64-apple-macos14.0",
          absl::StrCat(
              "-Xwrapped-swift=-explicit-compile-module-from-interface=",
              swiftmodule_dir),
      },
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(
      exact_runner.GetArgs(),
      ElementsAre("-target", "arm64-apple-macos14.0", arm64_interface,
                  "-enable-library-evolution", "-module-name", "FooExact"));

  SwiftRunner direct_runner(
      {
          "swiftc",
          "-target",
          "arm64-apple-macos14.0",
          absl::StrCat(
              "-Xwrapped-swift=-explicit-compile-module-from-interface=",
              arm64_interface),
      },
      /*force_response_file=*/false,
      /*get_current_directory=*/GetCurrentDirectoryForTest,
      /*job_env=*/GetJobEnvForTest());
  EXPECT_THAT(
      direct_runner.GetArgs(),
      ElementsAre("-target", "arm64-apple-macos14.0", arm64_interface,
                  "-enable-library-evolution", "-module-name", "FooExact"));
}

std::string WriteExecutableScript(absl::string_view dir, absl::string_view name,
                                  absl::string_view body) {
  std::string path = absl::StrCat(dir, "/", name);
  {
    std::ofstream out(path);
    out << "#!/bin/sh\n" << body;
  }
  chmod(path.c_str(), S_IRWXU);
  return path;
}

std::string ReadFileContents(const std::string& path) {
  std::ifstream in(path);
  return std::string((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
}

TEST(SwiftRunnerTest, RunProcessDiagnosticsUpgradesRequestedWarningsToErrors) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("diag_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string mock_swiftc = WriteExecutableScript(
      temp_dir->GetPath(), "mock_swiftc.sh",
      "printf 'foo.swift:1:2: warning: bad thing [upgraded_diag]\\n' >&2\n"
      "printf 'foo.swift:3:4: warning: minor thing [kept_diag]\\n' >&2\n"
      "printf '\\033[1;35mwarning: \\033[0mcolored [color_diag]\\033[0m\\n' "
      ">&2\n"
      "exit 0\n");

  {
    SwiftRunner failing_runner(
        {
            mock_swiftc,
            "-Xwrapped-swift=-warning-as-error=upgraded_diag",
            "-Xwrapped-swift=-warning-as-error=color_diag",
            "-Xwrapped-swift=-macro-expansion-dir=" +
                absl::StrCat(temp_dir->GetPath(), "/macros"),
        },
        /*force_response_file=*/false);
    std::ostringstream stdout_stream;
    std::ostringstream stderr_stream;
    int exit_code = failing_runner.Run(stdout_stream, stderr_stream);
    EXPECT_THAT(exit_code, Eq(1));
    EXPECT_THAT(stderr_stream.str(),
                HasSubstr("foo.swift:1:2: error (upgraded from warning): bad "
                          "thing [upgraded_diag]"));
    EXPECT_THAT(stderr_stream.str(),
                HasSubstr("foo.swift:3:4: warning: minor thing [kept_diag]"));
    EXPECT_THAT(
        stderr_stream.str(),
        HasSubstr("\x1b[1;31merror (upgraded from warning): \x1b[0mcolored "
                  "[color_diag]\x1b[0m"));
  }

  {
    SwiftRunner passing_runner(
        {
            mock_swiftc,
            "-Xwrapped-swift=-warning-as-error=unrelated_diag",
            "-Xwrapped-swift=-macro-expansion-dir=" +
                absl::StrCat(temp_dir->GetPath(), "/macros2"),
        },
        /*force_response_file=*/false);
    std::ostringstream stdout_stream;
    std::ostringstream stderr_stream;
    int exit_code = passing_runner.Run(stdout_stream, stderr_stream);
    EXPECT_THAT(exit_code, Eq(0));
    EXPECT_THAT(stderr_stream.str(),
                Not(HasSubstr("error (upgraded from warning)")));
    EXPECT_THAT(stderr_stream.str(),
                HasSubstr("foo.swift:1:2: warning: bad thing [upgraded_diag]"));
  }
}

TEST(SwiftRunnerTest, RunPerformLayeringCheckDetectsViolationsAndMapsAliases) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("layering_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string deps_modules_path =
      absl::StrCat(temp_dir->GetPath(), "/target.deps-modules");
  std::string imported_modules_path =
      absl::StrCat(temp_dir->GetPath(), "/target.imported-modules");
  {
    std::ofstream out(deps_modules_path);
    out << "AllowedMod\n";
  }

  std::string mock_swiftc = WriteExecutableScript(
      temp_dir->GetPath(), "mock_swiftc.sh",
      absl::StrCat("params_file=\"${1#@}\"\n"
                   "if grep -q -- '-emit-imported-modules' \"$params_file\"; "
                   "then\n"
                   "  cat << 'EOF' > '",
                   imported_modules_path,
                   "'\n"
                   "AllowedMod\n"
                   "SelfMod\n"
                   "Swift\n"
                   "_Concurrency\n"
                   "PhysicalDisallowedMod\n"
                   "DirectDisallowedMod\n"
                   "EOF\n"
                   "fi\n"
                   "exit 0\n"));

  {
    SwiftRunner failing_runner(
        {
            mock_swiftc,
            "-module-name",
            "SelfMod",
            "-module-alias",
            "LogicalDisallowedMod=PhysicalDisallowedMod",
            "-Xwrapped-swift=-bazel-target-label=//some/pkg:my_target",
            absl::StrCat("-Xwrapped-swift=-layering-check-deps-modules=",
                         deps_modules_path),
            absl::StrCat("-Xwrapped-swift=-macro-expansion-dir=",
                         temp_dir->GetPath(), "/macros"),
        },
        /*force_response_file=*/false);
    std::ostringstream stdout_stream;
    std::ostringstream stderr_stream;
    int exit_code = failing_runner.Run(stdout_stream, stderr_stream);
    EXPECT_THAT(exit_code, Eq(1));
    EXPECT_THAT(stderr_stream.str(), HasSubstr("Layering violation in "));
    EXPECT_THAT(stderr_stream.str(), HasSubstr("//some/pkg:my_target"));
    EXPECT_THAT(
        stderr_stream.str(),
        HasSubstr("    DirectDisallowedMod\n    LogicalDisallowedMod\n"));
    EXPECT_THAT(stderr_stream.str(), Not(HasSubstr("AllowedMod")));
    EXPECT_THAT(stderr_stream.str(), Not(HasSubstr("SelfMod")));
    EXPECT_THAT(stderr_stream.str(), Not(HasSubstr("PhysicalDisallowedMod")));
  }

  // Now add the missing physical modules to deps-modules and verify layering
  // check succeeds.
  {
    std::ofstream out(deps_modules_path);
    out << "AllowedMod\n"
        << "PhysicalDisallowedMod\n"
        << "DirectDisallowedMod\n";
  }
  {
    SwiftRunner passing_runner(
        {
            mock_swiftc,
            "-module-name",
            "SelfMod",
            "-module-alias",
            "LogicalDisallowedMod=PhysicalDisallowedMod",
            "-Xwrapped-swift=-bazel-target-label=//some/pkg:my_target",
            absl::StrCat("-Xwrapped-swift=-layering-check-deps-modules=",
                         deps_modules_path),
            absl::StrCat("-Xwrapped-swift=-macro-expansion-dir=",
                         temp_dir->GetPath(), "/macros2"),
        },
        /*force_response_file=*/false);
    std::ostringstream stdout_stream;
    std::ostringstream stderr_stream;
    int exit_code = passing_runner.Run(stdout_stream, stderr_stream);
    EXPECT_THAT(exit_code, Eq(0));
    EXPECT_THAT(stderr_stream.str(), Eq(""));
  }
}

TEST(SwiftRunnerTest, RunPerformJsonAstDumpWritesFallbackOnCrash) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("ast_dump_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string mock_swiftc =
      WriteExecutableScript(temp_dir->GetPath(), "mock_swiftc.sh",
                            "params_file=\"${1#@}\"\n"
                            "if grep -q -- '-dump-ast' \"$params_file\"; then\n"
                            "  exit 1\n"
                            "fi\n"
                            "exit 0\n");

  // Case 1: Explicit comma-separated AST paths via -emit-json-ast=<paths>.
  std::string ast1_path = absl::StrCat(temp_dir->GetPath(), "/a.ast.json");
  std::string ast2_path = absl::StrCat(temp_dir->GetPath(), "/b.ast.json");
  {
    SwiftRunner runner(
        {
            mock_swiftc,
            absl::StrCat("-Xwrapped-swift=-emit-json-ast=", ast1_path, ",",
                         ast2_path),
            absl::StrCat("-Xwrapped-swift=-macro-expansion-dir=",
                         temp_dir->GetPath(), "/macros1"),
        },
        /*force_response_file=*/false);
    std::ostringstream stdout_stream;
    std::ostringstream stderr_stream;
    EXPECT_THAT(runner.Run(stdout_stream, stderr_stream), Eq(0));
    EXPECT_THAT(ReadFileContents(ast1_path), Eq("{}\n"));
    EXPECT_THAT(ReadFileContents(ast2_path), Eq("{}\n"));
  }

  // Case 2: Unqualified -emit-json-ast reading paths from -output-file-map.
  std::string map_ast_path =
      absl::StrCat(temp_dir->GetPath(), "/from_map.ast.json");
  std::string output_file_map_path =
      absl::StrCat(temp_dir->GetPath(), "/output_file_map.json");
  {
    std::ofstream out(output_file_map_path);
    out << "{\n"
        << "  \"foo.swift\": {\"ast-dump\": \"" << map_ast_path << "\"},\n"
        << "  \"bar.swift\": {\"object\": \"bar.o\"}\n"
        << "}\n";
  }
  {
    SwiftRunner runner(
        {
            mock_swiftc,
            "-output-file-map",
            output_file_map_path,
            "-Xwrapped-swift=-emit-json-ast",
            absl::StrCat("-Xwrapped-swift=-macro-expansion-dir=",
                         temp_dir->GetPath(), "/macros2"),
        },
        /*force_response_file=*/false);
    std::ostringstream stdout_stream;
    std::ostringstream stderr_stream;
    EXPECT_THAT(runner.Run(stdout_stream, stderr_stream), Eq(0));
    EXPECT_THAT(ReadFileContents(map_ast_path), Eq("{}\n"));
  }
}

TEST(SwiftRunnerTest, RunPerformGeneratedHeaderRewriting) {
  std::unique_ptr<TempDirectory> temp_dir =
      TempDirectory::Create("header_rewriter_test.XXXXXX");
  ASSERT_NE(temp_dir, nullptr);

  std::string mock_swiftc =
      WriteExecutableScript(temp_dir->GetPath(), "mock_swiftc.sh", "exit 0\n");
  std::string mock_rewriter = WriteExecutableScript(
      temp_dir->GetPath(), "mock_rewriter.sh", "echo \"rewriter: $*\"\n");

  SwiftRunner runner(
      {
          mock_swiftc,
          "-module-name",
          "HeaderMod",
          absl::StrCat("-Xwrapped-swift=-generated-header-rewriter=",
                       mock_rewriter),
          "-Xwrapped-swift=-tool-arg=generated_header_rewriter=--custom-flag",
          absl::StrCat("-Xwrapped-swift=-macro-expansion-dir=",
                       temp_dir->GetPath(), "/macros"),
      },
      /*force_response_file=*/false);
  std::ostringstream stdout_stream;
  std::ostringstream stderr_stream;
  EXPECT_THAT(runner.Run(stdout_stream, stderr_stream), Eq(0));
  EXPECT_THAT(stdout_stream.str(),
              HasSubstr(absl::StrCat("rewriter: --custom-flag -- ", mock_swiftc,
                                     " @")));
}

}  // namespace
}  // namespace bazel_rules_swift
