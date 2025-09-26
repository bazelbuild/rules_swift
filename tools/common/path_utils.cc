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

#include "tools/common/path_utils.h"

#include <string>

#include "absl/strings/str_cat.h"

namespace bazel_rules_swift {

namespace {

size_t ExtensionStartPosition(absl::string_view path, bool all_extensions) {
  size_t last_slash = path.rfind('/');
  size_t dot;

  if (all_extensions) {
    // Find the first dot, signifying the first of all extensions.
    if (last_slash != absl::string_view::npos) {
      dot = path.find('.', last_slash);
    } else {
      dot = path.find('.');
    }
  } else {
    // Find the last extension only.
    dot = path.rfind('.');
    if (dot < last_slash) {
      // If the dot was part of a previous path segment, treat it as if it
      // wasn't found (it's not an extension of the filename).
      dot = absl::string_view::npos;
    }
  }

  return dot;
}

}  // namespace

absl::string_view Basename(absl::string_view path) {
  if (size_t last_slash = path.rfind('/');
      last_slash != absl::string_view::npos) {
    return path.substr(last_slash + 1);
  }
  return path;
}

absl::string_view Dirname(absl::string_view path) {
  if (size_t last_slash = path.rfind('/');
      last_slash != absl::string_view::npos) {
    return path.substr(0, last_slash);
  }
  return absl::string_view();
}

absl::string_view GetExtension(absl::string_view path, bool all_extensions) {
  if (size_t dot = ExtensionStartPosition(path, all_extensions);
      dot != absl::string_view::npos) {
    return path.substr(dot);
  }
  return "";
}

std::string ReplaceExtension(absl::string_view path,
                             absl::string_view new_extension,
                             bool all_extensions) {
  if (size_t dot = ExtensionStartPosition(path, all_extensions);
      dot != absl::string_view::npos) {
    return absl::StrCat(path.substr(0, dot), new_extension);
  }

  // If there was no dot append the extension to the path.
  return absl::StrCat(path, new_extension);
}

}  // namespace bazel_rules_swift
