// Copyright 2019 The Bazel Authors. All rights reserved.
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

#include <filesystem>
#include <fstream>
#include <map>
#include <nlohmann/json.hpp>
#include <string>

namespace {

// Returns the given path transformed to point to the incremental storage area.
// For example, "bazel-out/config/{genfiles,bin}/path" becomes
// "bazel-out/config/{genfiles,bin}/_swift_incremental/path".
// When split compiling we need different directories, as the various swiftdeps
// and priors files conflict.
static std::string MakeIncrementalOutputPath(std::string path,
                                             bool is_derived) {
  auto bin_index = path.find("/bin/");
  if (bin_index != std::string::npos) {
    if (is_derived) {
      path.replace(bin_index, 5, "/bin/_swift_incremental_derived/");
    } else {
      path.replace(bin_index, 5, "/bin/_swift_incremental/");
    }
    return path;
  }
  auto genfiles_index = path.find("/genfiles/");
  if (genfiles_index != std::string::npos) {
    if (is_derived) {
      path.replace(genfiles_index, 10, "/genfiles/_swift_incremental_derived/");
    } else {
      path.replace(genfiles_index, 10, "/genfiles/_swift_incremental/");
    }
    return path;
  }
  return path;
}

};  // end namespace

void OutputFileMap::ReadFromPath(const std::string& path) {
  std::ifstream stream(path);
  stream >> json_;
  UpdateForIncremental(path);
}

std::string OutputFileMap::AddOutput(const std::string& path) {
  auto incremental_path = MakeIncrementalOutputPath(path, is_derived_);
  incremental_outputs_[path] = incremental_path;
  return incremental_path;
}

void OutputFileMap::WriteToPath(const std::string& path) {
  std::ofstream stream(path);
  stream << json_;
}

void OutputFileMap::UpdateForIncremental(const std::string& path) {
  is_derived_ = path.find(".derived_output_file_map.json") != std::string::npos;

  nlohmann::json new_output_file_map;
  std::map<std::string, std::string> incremental_outputs;
  std::vector<std::string> incremental_dependencies;

  // The empty string key is used to represent outputs that are for the whole
  // module, rather than for a particular source file.
  nlohmann::json module_map;
  // Derive the swiftdeps file name from the .output-file-map.json name.
  std::string new_path =
      std::filesystem::path(path).replace_extension(".swiftdeps").string();
  auto swiftdeps_path = MakeIncrementalOutputPath(new_path, is_derived_);
  module_map["swift-dependencies"] = swiftdeps_path;
  incremental_dependencies.push_back(swiftdeps_path);
  new_output_file_map[""] = module_map;

  for (auto& element : json_.items()) {
    auto src = element.key();
    auto outputs = element.value();

    nlohmann::json src_map;
    std::string swiftdeps_path;

    // Process the outputs for the current source file.
    for (auto& output : outputs.items()) {
      auto kind = output.key();
      auto path = output.value().get<std::string>();

      if (kind == "object" || kind == "const-values") {
        // If the file kind is "object" or "const-values", we want to update the
        // path to point to the incremental storage area and then add a
        // "swift-dependencies" in the same location.
        auto new_path = MakeIncrementalOutputPath(path, is_derived_);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;

        if (swiftdeps_path.empty()) {
          swiftdeps_path = std::filesystem::path(new_path)
                               .replace_extension(".swiftdeps")
                               .string();
        }

        incremental_dependencies.push_back(swiftdeps_path);
      } else if (kind == "swiftdoc" || kind == "swiftinterface" ||
                 kind == "swiftmodule" || kind == "swiftsourceinfo") {
        // Module/interface outputs should be moved to the incremental storage
        // area without additional processing.
        auto new_path = MakeIncrementalOutputPath(path, is_derived_);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;

        if (swiftdeps_path.empty()) {
          swiftdeps_path = std::filesystem::path(new_path)
                               .replace_extension(".swiftdeps")
                               .string();
        }

        incremental_dependencies.push_back(swiftdeps_path);
      } else if (kind == "swift-dependencies") {
        // Only derived-file maps need explicit per-source dependency paths.
        // So we ignore other entries, including those added by a previous
        // rewrite.
        if (is_derived_ && !src.empty()) {
          swiftdeps_path = MakeIncrementalOutputPath(path, is_derived_);
          incremental_dependencies.push_back(swiftdeps_path);

          // Module-only compilations also produce per-source partial modules.
          // The driver checks that all outputs exist before skipping a source;
          // leaving these in its temporary directory forces every source to be
          // recompiled even when its swiftdeps are available. We keep the
          // partial modules beside the swiftdeps, without copying either back
          // to Bazel. Some driver modes skip partial compilation jobs entirely,
          // so these files are not required outputs of every invocation.
          src_map["swiftmodule"] = std::filesystem::path(swiftdeps_path)
                                       .replace_extension(".swiftmodule")
                                       .string();
        }
      } else {
        // Otherwise, just copy the mapping over verbatim.
        src_map[kind] = path;
      }
    }

    // When split compiling both output_file_maps need src level swiftdeps
    if (!swiftdeps_path.empty()) {
      src_map["swift-dependencies"] = swiftdeps_path;
    }

    new_output_file_map[src] = src_map;
  }

  json_ = new_output_file_map;
  incremental_outputs_ = incremental_outputs;
  incremental_dependencies_ = incremental_dependencies;
}
