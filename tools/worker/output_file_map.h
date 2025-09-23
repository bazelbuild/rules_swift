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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_OUTPUT_FILE_MAP_H
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_OUTPUT_FILE_MAP_H

#include <map>
#include <nlohmann/json.hpp>
#include <string>

// Supports loading a `swiftc` output file map.
//
// See
// https://github.com/apple/swift/blob/master/docs/Driver.md#output-file-maps
// for more information on how the Swift driver uses this file.
class OutputFileMap {
 public:
  explicit OutputFileMap() {}

  // The in-memory JSON-based representation of the output file map.
  const nlohmann::json &json() const { return json_; }

  // Get output files of a specific kind from the map
  std::vector<std::string> get_outputs_by_type(const std::string& type) const;

  // Reads the output file map from the JSON file at the given path.
  void ReadFromPath(const std::string &path);

 private:
  nlohmann::json json_;
};

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_WORKER_OUTPUT_FILE_MAP_H_
