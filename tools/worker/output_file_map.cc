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

namespace bazel_rules_swift {

// Returns the given path with an `.incremental` extension fragment interjected
// just before the existing extension so that the file will persist after the
// action has completed (because Bazel will not be tracking it). For example,
// "bazel-bin/my/package/file.o" becomes
// "bazel-bin/my/package/file.incremental.o".
std::string MakeIncrementalOutputPath(absl::string_view path) {
  return ReplaceExtension(path,
                          absl::StrCat(".incremental", GetExtension(path)));
}

void OutputFileMap::ReadFromPath(absl::string_view path,
                                 absl::string_view swiftmodule_path) {
  std::ifstream stream((std::string(path)));
  stream >> json_;
  UpdateForIncremental(path, swiftmodule_path);
}

void OutputFileMap::WriteToPath(absl::string_view path) {
  std::ofstream stream((std::string(path)));
  stream << json_;
}

void OutputFileMap::UpdateForIncremental(absl::string_view path,
                                         absl::string_view swiftmodule_path) {
  nlohmann::json new_output_file_map;
  incremental_outputs_.clear();

  // The empty string key is used to represent outputs that are for the whole
  // module, rather than for a particular source file.
  nlohmann::json module_map;

  // Derive the swiftdeps file name from the .output-file-map.json name.
  module_map["swift-dependencies"] = MakeIncrementalOutputPath(
      ReplaceExtension(path, ".swiftdeps", /*all_extensions=*/true));
  new_output_file_map[""] = module_map;

  for (auto &[src, outputs] : json_.items()) {
    nlohmann::json src_map;

    // Process the outputs for the current source file.
    for (auto &[kind, path_value] : outputs.items()) {
      auto path = path_value.get<std::string>();

      if (kind == "object") {
        // If the file kind is "object", update the path to point to the
        // incremental storage area.
        std::string new_object_path = MakeIncrementalOutputPath(path);
        src_map[kind] = new_object_path;
        incremental_outputs_[path] = new_object_path;

        // Add "swiftmodule" (for the partial .swiftmodule file) and
        // "swift-dependencies" entries in the same location.
        src_map["swift-dependencies"] =
            ReplaceExtension(new_object_path, ".swiftdeps");
        src_map["swiftmodule"] =
            ReplaceExtension(new_object_path, ".swiftmodule");
      } else if (kind == "swiftdoc" || kind == "swiftinterface" ||
                 kind == "swiftmodule" || kind == "swiftsourceinfo" ||
                 kind == "swift-dependencies") {
        // If any of these entries were already present, ignore them. (This
        // shouldn't happen because the build rules won't do this, but check
        // just in case.)
        std::cerr << " There was a '" << kind << "' entry for " << src
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

  incremental_outputs_[swiftmodule_path] =
      MakeIncrementalOutputPath(swiftmodule_path);

  std::string swiftdoc_path =
      ReplaceExtension(swiftmodule_path, ".swiftdoc", /*all_extensions=*/true);
  incremental_outputs_[swiftdoc_path] =
      MakeIncrementalOutputPath(swiftdoc_path);

  std::string swiftsourceinfo_path = ReplaceExtension(
      swiftmodule_path, ".swiftsourceinfo", /*all_extensions=*/true);
  incremental_outputs_[swiftsourceinfo_path] =
      MakeIncrementalOutputPath(swiftsourceinfo_path);
}

}  // namespace bazel_rules_swift
