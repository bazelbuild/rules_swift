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

#include <map>
#include <string>

// Finds and replaces all instances of oldsub with newsub, in-place on str.
// Returns true if the string was changed.
static bool FindAndReplace(const std::string &oldsub, const std::string &newsub,
                           std::string *str) {
  int start = 0;
  bool changed = false;
  while ((start = str->find(oldsub, start)) != std::string::npos) {
    changed = true;
    str->replace(start, oldsub.length(), newsub);
    start += newsub.length();
  }
  return changed;
}

bool MakeSubstitutions(std::string *arg,
                       const std::map<std::string, std::string> &mappings) {
  bool changed = false;

  // Replace placeholders in the string with their actual values.
  for (std::pair<std::string, std::string> mapping : mappings) {
    changed |= FindAndReplace(mapping.first, mapping.second, arg);
  }

  return changed;
}
