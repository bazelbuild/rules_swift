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
#include <string>

#include "absl/container/btree_map.h"
#include "absl/strings/string_view.h"
#include "tools/common/path_utils.h"
#include <nlohmann/json.hpp>

namespace {

// Returns the given path transformed to point to the incremental storage area.
// For example, "bazel-out/config/{genfiles,bin}/path" becomes
// "bazel-out/config/{genfiles,bin}/_swift_incremental/path".
static std::string MakeIncrementalOutputPath(absl::string_view path) {
  std::string new_path(path);
  size_t bin_index = new_path.find("/bin/");
  if (bin_index != std::string::npos) {
    new_path.replace(bin_index, 5, "/bin/_swift_incremental/");
    return new_path;
  }
  size_t genfiles_index = new_path.find("/genfiles/");
  if (genfiles_index != std::string::npos) {
    new_path.replace(genfiles_index, 10, "/genfiles/_swift_incremental/");
    return new_path;
  }
  return new_path;
}

};  // end namespace

void OutputFileMap::ReadFromPath(absl::string_view path) {
  std::ifstream stream((std::string(path)));
  stream >> json_;
  UpdateForIncremental(path);
}

void OutputFileMap::WriteToPath(absl::string_view path) {
  std::ofstream stream((std::string(path)));
  stream << json_;
}

void OutputFileMap::UpdateForIncremental(absl::string_view path) {
  nlohmann::json new_output_file_map;
  absl::btree_map<std::string, std::string> incremental_outputs;

  // The empty string key is used to represent outputs that are for the whole
  // module, rather than for a particular source file.
  nlohmann::json module_map;
  // Derive the swiftdeps file name from the .output-file-map.json name.
  std::string new_path =
      ReplaceExtension(path, ".swiftdeps", /*all_extensions=*/true);
  std::string swiftdeps_path = MakeIncrementalOutputPath(new_path);
  module_map["swift-dependencies"] = swiftdeps_path;
  new_output_file_map[""] = module_map;

  for (auto &[src, outputs] : json_.items()) {
    nlohmann::json src_map;

    // Process the outputs for the current source file.
    for (auto &[kind, path_value] : outputs.items()) {
      auto path = path_value.get<std::string>();

      if (kind == "object") {
        // If the file kind is "object", we want to update the path to point to
        // the incremental storage area and then add a "swift-dependencies"
        // in the same location.
        std::string new_path = MakeIncrementalOutputPath(path);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;

        std::string swiftdeps_path = ReplaceExtension(new_path, ".swiftdeps");
        src_map["swift-dependencies"] = swiftdeps_path;
      } else if (kind == "swiftdoc" || kind == "swiftinterface" ||
                 kind == "swiftmodule") {
        // Module/interface outputs should be moved to the incremental storage
        // area without additional processing.
        std::string new_path = MakeIncrementalOutputPath(path);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;
      } else if (kind == "swift-dependencies") {
        // If there was already a "swift-dependencies" entry present, ignore it.
        // (This shouldn't happen because the build rules won't do this, but
        // check just in case.)
        std::cerr << "There was a 'swift-dependencies' entry for " << src
                  << ", but the build rules should not have done this; "
                  << "ignoring it." << std::endl;
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
