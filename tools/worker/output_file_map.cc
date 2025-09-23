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
#include <iostream>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

void OutputFileMap::ReadFromPath(const std::string &path) {
  std::ifstream stream(path);
  stream >> json_;
}

std::vector<std::string> OutputFileMap::get_outputs_by_type(const std::string& type) const {
  std::vector<std::string> result;

  for (auto &element : json_.items()) {
    auto outputs = element.value();
    if (outputs.is_object() && outputs.contains(type)) {
      result.push_back(outputs[type].get<std::string>());
    }
  }

  return result;
}