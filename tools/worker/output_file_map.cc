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

#include <fstream>
#include <iostream>
#include <map>
#include <string>

#include "tools/common/path_utils.h"
#include <nlohmann/json.hpp>

namespace {

// Returns the given path transformed to point to the incremental storage area.
// For example, "bazel-out/config/{genfiles,bin}/path" becomes
// "bazel-out/config/{genfiles,bin}/_swift_incremental/path".
static std::string MakeIncrementalOutputPath(std::string path) {
  auto bin_index = path.find("/bin/");
  if (bin_index != std::string::npos) {
    path.replace(bin_index, 5, "/bin/_swift_incremental/");
    return path;
  }
  auto genfiles_index = path.find("/genfiles/");
  if (genfiles_index != std::string::npos) {
    path.replace(genfiles_index, 10, "/genfiles/_swift_incremental/");
    return path;
  }
  return path;
}

};  // end namespace

void OutputFileMap::ReadFromPath(const std::string &path) {
  std::ifstream stream(path);
  stream >> json_;
  UpdateForIncremental();
}

void OutputFileMap::WriteToPath(const std::string &path) {
  std::ofstream stream(path);
  stream << json_;
}

void OutputFileMap::UpdateForIncremental() {
  nlohmann::json new_output_file_map;
  std::map<std::string, std::string> incremental_outputs;

  for (auto &element : json_.items()) {
    auto src = element.key();
    auto outputs = element.value();

    // The empty string key is used to represent outputs that are for the whole
    // module, rather than for a particular source file.
    if (src.empty()) {
      nlohmann::json empty_map = outputs;
      auto path = outputs["swift-dependencies"].get<std::string>();
      auto new_path = MakeIncrementalOutputPath(path);
      empty_map["swift-dependencies"] = new_path;
      incremental_outputs[path] = new_path;
      new_output_file_map[""] = empty_map;
      continue;
    }

    nlohmann::json src_map;

    // Process the outputs for the current source file.
    for (auto &output : outputs.items()) {
      auto kind = output.key();
      auto path = output.value().get<std::string>();

      if (kind == "object") {
        // If the file kind is "object", we want to update the path to point to
        // the incremental storage area and then add a "swift-dependencies"
        // in the same location.
        auto new_path = MakeIncrementalOutputPath(path);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;

        auto swiftdeps_path = ReplaceExtension(new_path, ".swiftdeps");
        src_map["swift-dependencies"] = swiftdeps_path;
      } else if (kind == "swiftdoc" || kind == "swiftinterface" ||
                 kind == "swiftmodule") {
        // Module/interface outputs should be moved to the incremental storage
        // area without additional processing.
        auto new_path = MakeIncrementalOutputPath(path);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;
      } else if (kind == "swift-dependencies") {
        // If there was already a "swift-dependencies" entry present, ignore it.
        // (This shouldn't happen because the build rules won't do this, but
        // check just in case.)
        std::cerr << "There was a 'swift-dependencies' entry for " << src
                  << ", but the build rules should not have done this; "
                  << "ignoring it.\n";
      } else {
        // Otherwise, just copy the mapping over verbatim.
        src_map[kind] = path;
      }
    }

    new_output_file_map[src] = src_map;
  }

  json_ = new_output_file_map;
  incremental_outputs_ = incremental_outputs;
}
