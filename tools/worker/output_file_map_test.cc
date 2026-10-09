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

#include "tools/worker/output_file_map.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>
#include <string>

namespace {

void Check(bool condition, const std::string& message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}

void WriteFile(const std::filesystem::path& path, const std::string& content) {
  if (path.has_parent_path()) {
    std::filesystem::create_directories(path.parent_path());
  }
  std::ofstream stream(path);
  stream << content;
}

nlohmann::json ReadJson(const std::string& path) {
  nlohmann::json json;
  std::ifstream stream(path);
  stream >> json;
  return json;
}

}  // namespace

int main() {
  const char* test_tmpdir = std::getenv("TEST_TMPDIR");
  Check(test_tmpdir != nullptr, "TEST_TMPDIR is not set");
  std::filesystem::current_path(test_tmpdir);

  // A tree artifact of sources, including a nested directory, a symlink, and a
  // file that isn't Swift source.
  // Sandboxes and some strategies stage tree artifact files as symlinks.
  WriteFile("elsewhere/A.swift", "");
  std::filesystem::create_directories("out/bin/gen.swift");
  std::filesystem::create_symlink(
      std::filesystem::absolute("elsewhere/A.swift"),
      "out/bin/gen.swift/A.swift");
  WriteFile("out/bin/gen.swift/sub/B.swift", "");
  WriteFile("out/bin/gen.swift/README.md", "");
  WriteFile("Regular.swift", "");

  WriteFile("out/bin/lib.output_file_map.json", R"({
    "": {"const-values": "out/bin/lib.swiftconstvalues"},
    "Regular.swift": {"object": "out/bin/lib_objs/Regular.swift.o"},
    "out/bin/gen.swift": {
      "object": "out/bin/lib_objs/gen.swift_o",
      "ast-dump": "out/bin/lib_objs/gen.swift_ast",
      "index-unit-output-path": "out/bin/lib_objs/gen.swift_o"
    }
  })");
  std::string error;
  Check(OutputFileMap::WriteExpanded(
            "out/bin/lib.output_file_map.json", "expanded.json",
            OutputFileMap::ActionOutputs::kCompile, &error),
        "expansion failed: " + error);

  auto json = ReadJson("expanded.json");
  Check(json.size() == 4, "expected 4 entries, got: " + json.dump());
  Check(!json.contains("out/bin/gen.swift"),
        "directory entry was not replaced");
  Check(!json.contains("out/bin/gen.swift/README.md"),
        "non-Swift file expanded");
  Check(json[""]["const-values"] == "out/bin/lib.swiftconstvalues",
        "whole-module entry changed");
  Check(json["Regular.swift"]["object"] == "out/bin/lib_objs/Regular.swift.o",
        "file entry changed");

  auto& a = json["out/bin/gen.swift/A.swift"];
  Check(a["object"] == "out/bin/lib_objs/gen.swift_o/A.swift.o",
        "A.swift object: " + a.dump());
  Check(a["ast-dump"] == "out/bin/lib_objs/gen.swift_ast/A.swift.ast",
        "A.swift ast: " + a.dump());
  Check(a["index-unit-output-path"] == "out/bin/lib_objs/gen.swift_o/A.swift.o",
        "A.swift index unit: " + a.dump());

  auto& b = json["out/bin/gen.swift/sub/B.swift"];
  Check(b["object"] == "out/bin/lib_objs/gen.swift_o/sub/B.swift.o",
        "sub/B.swift object: " + b.dump());

  // Only the directories of the outputs the action writes are created; the AST
  // directory belongs to the AST dump action.
  Check(std::filesystem::is_directory("out/bin/lib_objs/gen.swift_o/sub"),
        "object subdirectory was not created");
  Check(!std::filesystem::exists("out/bin/lib_objs/gen.swift_ast"),
        "AST directory created by the compile action");
  Check(OutputFileMap::WriteExpanded(
            "out/bin/lib.output_file_map.json", "expanded_ast.json",
            OutputFileMap::ActionOutputs::kDumpAst, &error),
        "AST expansion failed: " + error);
  Check(std::filesystem::is_directory("out/bin/lib_objs/gen.swift_ast/sub"),
        "AST subdirectory was not created");

  // Incremental mode expands directories before moving outputs to the
  // incremental storage area, so each file gets its own outputs there.
  OutputFileMap output_file_map;
  Check(output_file_map.ReadFromPath("out/bin/lib.output_file_map.json", "", "",
                                     /*expand_source_directories=*/true),
        "reading failed: " + output_file_map.error());
  auto outputs = output_file_map.incremental_outputs();
  Check(outputs.count("out/bin/lib_objs/gen.swift_o/sub/B.swift.o") == 1,
        "incremental outputs missing sub/B.swift.o");
  Check(outputs["out/bin/lib_objs/gen.swift_o/sub/B.swift.o"] ==
            "out/bin/_swift_incremental/lib_objs/gen.swift_o/sub/B.swift.o",
        "unexpected incremental path for sub/B.swift.o");

  // Without expansion, the map is read as-is.
  OutputFileMap unexpanded;
  Check(unexpanded.ReadFromPath("out/bin/lib.output_file_map.json", "", ""),
        "reading without expansion failed");
  Check(unexpanded.json().contains("out/bin/gen.swift"),
        "map expanded although expansion was not requested");

  // Errors are reported rather than ignored.
  WriteFile("out/bin/unknown.output_file_map.json",
            R"({"out/bin/gen.swift": {"new-kind": "out/bin/x"}})");
  Check(!OutputFileMap::WriteExpanded(
            "out/bin/unknown.output_file_map.json", "unknown.json",
            OutputFileMap::ActionOutputs::kCompile, &error) &&
            error.find("new-kind") != std::string::npos,
        "unknown kind not reported: " + error);

  WriteFile("out/bin/malformed.output_file_map.json", "{");
  Check(!OutputFileMap::WriteExpanded(
            "out/bin/malformed.output_file_map.json", "malformed.json",
            OutputFileMap::ActionOutputs::kCompile, &error),
        "malformed map not reported");

  WriteFile("out/bin/unreadable.swift/C.swift", "");
  std::filesystem::permissions("out/bin/unreadable.swift",
                               std::filesystem::perms::none);
  WriteFile("out/bin/unreadable.output_file_map.json",
            R"({"out/bin/unreadable.swift": {"object": "out/bin/x"}})");
  bool unreadable_ok = OutputFileMap::WriteExpanded(
      "out/bin/unreadable.output_file_map.json", "unreadable.json",
      OutputFileMap::ActionOutputs::kCompile, &error);
  std::filesystem::permissions("out/bin/unreadable.swift",
                               std::filesystem::perms::owner_all);
  Check(!unreadable_ok, "unreadable source directory not reported");

  return 0;
}
