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

#include <sys/stat.h>

#include <cerrno>
#include <fstream>
#include <iterator>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <utility>

#include "testing/base/public/gmock.h"
#include "testing/base/public/gunit.h"
#include "absl/container/flat_hash_map.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "absl/strings/str_cat.h"
#include "tools/common/bazel_substitutions.h"
#include "tools/common/color.h"
#include "tools/common/file_system.h"
#include "tools/common/path_utils.h"
#include "tools/common/process.h"
#include "tools/common/status.h"
#include "tools/common/target_triple.h"
#include "tools/common/temp_file.h"

namespace bazel_rules_swift {
namespace {

using ::testing::Eq;
using ::testing::HasSubstr;

TEST(TargetTripleTest, ParsesThreeComponentTriple) {
  std::optional<TargetTriple> triple =
      TargetTriple::Parse("arm64-apple-macos14.0");
  ASSERT_TRUE(triple.has_value());
  EXPECT_THAT(triple->Arch(), Eq("arm64"));
  EXPECT_THAT(triple->Vendor(), Eq("apple"));
  EXPECT_THAT(triple->OS(), Eq("macos14.0"));
  EXPECT_THAT(triple->Environment(), Eq(""));
  EXPECT_THAT(triple->TripleString(), Eq("arm64-apple-macos14.0"));
}

TEST(TargetTripleTest, ParsesFourComponentSimulatorTriple) {
  std::optional<TargetTriple> triple =
      TargetTriple::Parse("x86_64-apple-ios17.2-simulator");
  ASSERT_TRUE(triple.has_value());
  EXPECT_THAT(triple->Arch(), Eq("x86_64"));
  EXPECT_THAT(triple->Vendor(), Eq("apple"));
  EXPECT_THAT(triple->OS(), Eq("ios17.2"));
  EXPECT_THAT(triple->Environment(), Eq("simulator"));
  EXPECT_THAT(triple->TripleString(), Eq("x86_64-apple-ios17.2-simulator"));
}

TEST(TargetTripleTest, ParsesLinuxGnuTriple) {
  std::optional<TargetTriple> triple =
      TargetTriple::Parse("x86_64-unknown-linux-gnu");
  ASSERT_TRUE(triple.has_value());
  EXPECT_THAT(triple->Arch(), Eq("x86_64"));
  EXPECT_THAT(triple->Vendor(), Eq("unknown"));
  EXPECT_THAT(triple->OS(), Eq("linux"));
  EXPECT_THAT(triple->Environment(), Eq("gnu"));
  EXPECT_THAT(triple->TripleString(), Eq("x86_64-unknown-linux-gnu"));
}

TEST(TargetTripleTest, RejectsInvalidTriples) {
  EXPECT_FALSE(TargetTriple::Parse("").has_value());
  EXPECT_FALSE(TargetTriple::Parse("arm64").has_value());
  EXPECT_FALSE(TargetTriple::Parse("arm64-apple").has_value());
}

TEST(TargetTripleTest, WithoutOSVersionAndWithArch) {
  std::optional<TargetTriple> macos =
      TargetTriple::Parse("arm64-apple-macos14.5");
  ASSERT_TRUE(macos.has_value());
  TargetTriple unversioned_macos = macos->WithoutOSVersion();
  EXPECT_THAT(unversioned_macos.OS(), Eq("macos"));
  EXPECT_THAT(unversioned_macos.TripleString(), Eq("arm64-apple-macos"));
  EXPECT_THAT(unversioned_macos.WithArch("arm64e").TripleString(),
              Eq("arm64e-apple-macos"));

  std::optional<TargetTriple> sim =
      TargetTriple::Parse("arm64-apple-ios17.0-simulator");
  ASSERT_TRUE(sim.has_value());
  EXPECT_THAT(sim->WithoutOSVersion().TripleString(),
              Eq("arm64-apple-ios-simulator"));

  std::optional<TargetTriple> linux_triple =
      TargetTriple::Parse("aarch64-unknown-linux-gnu");
  ASSERT_TRUE(linux_triple.has_value());
  EXPECT_THAT(linux_triple->WithoutOSVersion().TripleString(),
              Eq("aarch64-unknown-linux-gnu"));
}

TEST(PathUtilsTest, BasenameAndDirname) {
  EXPECT_THAT(Basename("/foo/bar/baz.txt"), Eq("baz.txt"));
  EXPECT_THAT(Basename("baz.txt"), Eq("baz.txt"));
  EXPECT_THAT(Basename("/foo/bar/"), Eq(""));
  EXPECT_THAT(Basename(""), Eq(""));

  EXPECT_THAT(Dirname("/foo/bar/baz.txt"), Eq("/foo/bar"));
  EXPECT_THAT(Dirname("/baz.txt"), Eq(""));
  EXPECT_THAT(Dirname("baz.txt"), Eq(""));
  EXPECT_THAT(Dirname(""), Eq(""));
}

TEST(PathUtilsTest, GetExtension) {
  EXPECT_THAT(GetExtension("/foo/bar/baz.tar.gz"), Eq(".gz"));
  EXPECT_THAT(GetExtension("/foo/bar/baz.tar.gz", /*all_extensions=*/true),
              Eq(".tar.gz"));
  EXPECT_THAT(GetExtension("./baz.tar.gz"), Eq(".gz"));
  EXPECT_THAT(GetExtension("baz.tar.gz", /*all_extensions=*/true),
              Eq(".tar.gz"));
  EXPECT_THAT(GetExtension("/foo.dir/bar/baz"), Eq(""));
  EXPECT_THAT(GetExtension("/foo.dir/bar/baz", /*all_extensions=*/true),
              Eq(""));
  EXPECT_THAT(GetExtension("baz"), Eq(""));
}

TEST(PathUtilsTest, ReplaceExtension) {
  EXPECT_THAT(ReplaceExtension("/foo/bar/baz.tar.gz", ".out"),
              Eq("/foo/bar/baz.tar.out"));
  EXPECT_THAT(ReplaceExtension("/foo/bar/baz.tar.gz", ".out",
                               /*all_extensions=*/true),
              Eq("/foo/bar/baz.out"));
  EXPECT_THAT(ReplaceExtension("/foo.dir/bar/baz", ".out"),
              Eq("/foo.dir/bar/baz.out"));
  EXPECT_THAT(ReplaceExtension("baz", ".out", /*all_extensions=*/true),
              Eq("baz.out"));
}

TEST(BazelPlaceholderSubstitutionsTest, ExplicitSubstitutions) {
  BazelPlaceholderSubstitutions substitutions("/Applications/Xcode/Developer",
                                              "/Applications/Xcode/SDKs/Mac");
  std::string arg =
      "-I__BAZEL_XCODE_DEVELOPER_DIR__/usr/include "
      "-isysroot __BAZEL_XCODE_SDKROOT__";
  EXPECT_TRUE(substitutions.Apply(arg));
  EXPECT_THAT(arg, Eq("-I/Applications/Xcode/Developer/usr/include -isysroot "
                      "/Applications/Xcode/SDKs/Mac"));

  std::string unchanged = "-module-name Foo";
  EXPECT_FALSE(substitutions.Apply(unchanged));
  EXPECT_THAT(unchanged, Eq("-module-name Foo"));
}

TEST(BazelPlaceholderSubstitutionsTest, EnvironmentMapSubstitutions) {
  absl::flat_hash_map<std::string, std::string> env = {
      {"DEVELOPER_DIR", "/custom/developer"},
      {"SDKROOT", "/custom/sdk"},
  };
  BazelPlaceholderSubstitutions substitutions(env);

  std::string dev_arg = "__BAZEL_XCODE_DEVELOPER_DIR__/Platforms";
  EXPECT_TRUE(substitutions.Apply(dev_arg));
  EXPECT_THAT(dev_arg, Eq("/custom/developer/Platforms"));

  std::string sdk_arg = "__BAZEL_XCODE_SDKROOT__/System/Library";
  EXPECT_TRUE(substitutions.Apply(sdk_arg));
  EXPECT_THAT(sdk_arg, Eq("/custom/sdk/System/Library"));

  absl::flat_hash_map<std::string, std::string> empty_env = {
      {"DEVELOPER_DIR", ""},
  };
  BazelPlaceholderSubstitutions empty_substitutions(empty_env);
  std::string unreplaced = "__BAZEL_XCODE_DEVELOPER_DIR__/Platforms";
  EXPECT_FALSE(empty_substitutions.Apply(unreplaced));
  EXPECT_THAT(unreplaced, Eq("__BAZEL_XCODE_DEVELOPER_DIR__/Platforms"));
}

TEST(ColorTest, FormatsAnsiColorCodesAndReset) {
  std::ostringstream out;
  {
    WithColor colored(out, Color::kBoldRed);
    colored << "error: " << 42;
  }
  out << " plain";
  EXPECT_THAT(out.str(), Eq("\x1b[1;31merror: 42\x1b[0m plain"));
}

TEST(FileSystemAndTempFileTest, TempFileAndCopyFileLifecycle) {
  std::string temp_file_path;
  {
    std::unique_ptr<TempFile> temp_file =
        TempFile::Create("common_test_file.XXXXXX");
    ASSERT_NE(temp_file, nullptr);
    temp_file_path = std::string(temp_file->GetPath());
    EXPECT_TRUE(PathExists(temp_file_path));

    {
      std::ofstream out(temp_file_path);
      out << "hello rules_swift\n";
    }

    std::unique_ptr<TempDirectory> temp_dir =
        TempDirectory::Create("common_test_dir.XXXXXX");
    ASSERT_NE(temp_dir, nullptr);
    std::string nested_dir = absl::StrCat(temp_dir->GetPath(), "/a/b/c");
    EXPECT_TRUE(MakeDirs(nested_dir, S_IRWXU).ok());
    EXPECT_TRUE(PathExists(nested_dir));
    // Calling MakeDirs on an existing directory is idempotent.
    EXPECT_TRUE(MakeDirs(nested_dir, S_IRWXU).ok());

    std::string copied_path = absl::StrCat(nested_dir, "/copied.txt");
    EXPECT_TRUE(CopyFile(temp_file_path, copied_path).ok());
    EXPECT_TRUE(PathExists(copied_path));

    std::ifstream in(copied_path);
    std::string content((std::istreambuf_iterator<char>(in)),
                        std::istreambuf_iterator<char>());
    EXPECT_THAT(content, Eq("hello rules_swift\n"));

    // Calling MakeDirs on an existing regular file fails.
    EXPECT_FALSE(MakeDirs(copied_path, S_IRWXU).ok());
  }
  EXPECT_FALSE(PathExists(temp_file_path));
  EXPECT_TRUE(PathExists(GetCurrentDirectory()));
}

TEST(StatusTest, MapsErrnoToAbseilStatusCode) {
  errno = ENOENT;
  absl::Status not_found = MakeStatusFromErrno("missing file");
  EXPECT_THAT(not_found.code(), Eq(absl::StatusCode::kNotFound));
  EXPECT_THAT(not_found.message(), HasSubstr("missing file"));

  errno = EEXIST;
  EXPECT_THAT(MakeStatusFromErrno("exists").code(),
              Eq(absl::StatusCode::kAlreadyExists));

  errno = EACCES;
  EXPECT_THAT(MakeStatusFromErrno("denied").code(),
              Eq(absl::StatusCode::kPermissionDenied));

  errno = EINVAL;
  EXPECT_THAT(MakeStatusFromErrno("invalid").code(),
              Eq(absl::StatusCode::kInvalidArgument));
}

TEST(ProcessTest, RunSubProcessAndAsyncProcessCaptureOutput) {
  std::ostringstream stdout_stream;
  std::ostringstream stderr_stream;
  int exit_code = RunSubProcess({"/bin/echo", "hello subprocess"},
                                /*env=*/nullptr, stdout_stream, stderr_stream);
  EXPECT_THAT(exit_code, Eq(0));
  EXPECT_THAT(stdout_stream.str(), Eq("hello subprocess\n"));
  EXPECT_THAT(stderr_stream.str(), Eq(""));

  std::unique_ptr<TempFile> resp = TempFile::Create("process_resp.XXXXXX");
  ASSERT_NE(resp, nullptr);
  {
    std::ofstream out(std::string(resp->GetPath()));
    out << "from_resp\n";
  }
  absl::flat_hash_map<std::string, std::string> env = GetCurrentEnvironment();
  env["CUSTOM_PROCESS_VAR"] = "val123";

  absl::StatusOr<std::unique_ptr<AsyncProcess>> proc =
      AsyncProcess::Spawn({"/bin/echo", "arg1"}, std::move(resp), &env);
  ASSERT_TRUE(proc.ok());
  absl::StatusOr<AsyncProcess::Result> result = (*proc)->WaitForTermination();
  ASSERT_TRUE(result.ok());
  EXPECT_THAT(result->exit_code, Eq(0));
  EXPECT_THAT(result->stdout, HasSubstr("arg1 @"));
}

}  // namespace
}  // namespace bazel_rules_swift
