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

#include "tools/worker/hermetic_symlink.h"

#include <cstdlib>
#include <iostream>

namespace bazel_rules_swift {

std::string NormalizeDeveloperDir(std::string developer_dir) {
  while (developer_dir.size() > 1 && developer_dir.back() == '/') {
    developer_dir.pop_back();
  }
  return developer_dir;
}

std::string DeveloperDirSymlinkName() {
  const char* xcode_version = std::getenv("XCODE_VERSION_OVERRIDE");
  // NOTE: Probably can't happen but multi-xcode race conditions are low risk
  // anyways
  if (xcode_version == nullptr || xcode_version[0] == '\0') {
    return "__bazel_developer_dir";
  }

  std::string suffix = xcode_version;
  for (char& ch : suffix) {
    if (ch == '.') {
      ch = '_';
    }
  }
  return "__bazel_developer_dir_" + suffix;
}

bool EnsureDirectorySymlink(const std::filesystem::path& link,
                            const std::filesystem::path& target) {
  std::error_code ec;
  auto parent = link.parent_path();
  if (!parent.empty()) {
    std::filesystem::create_directories(parent, ec);
    if (ec) {
      std::cerr << "error: failed to create symlink parent " << parent << ": "
                << ec.message() << "\n";
      return false;
    }
  }

  std::filesystem::create_directory_symlink(target, link, ec);
  if (!ec) {
    return true;
  }

  // With sandboxing disabled, multiple actions share the same execroot and can
  // race on creation. If the symlink already exists and points at the same
  // target, use it. Do not remove it which would introduce a new race.
  if (ec == std::errc::file_exists) {
    std::error_code read_ec;
    auto existing = std::filesystem::read_symlink(link, read_ec);
    if (!read_ec && existing == target) {
      return true;
    }
    std::cerr << "error: symlink " << link << " already exists but points to '"
              << (read_ec ? std::string("<unreadable>") : existing.string())
              << "' instead of '" << target.string() << "'\n";
    return false;
  }

  std::cerr << "error: failed to create symlink " << link << " -> "
            << target.string() << ": " << ec.message() << "\n";
  return false;
}

bool EnsureDeveloperDirSymlink(const std::string& developer_dir) {
  std::filesystem::path link =
      std::filesystem::current_path() / DeveloperDirSymlinkName();
  std::filesystem::path developer_path = NormalizeDeveloperDir(developer_dir);
  return EnsureDirectorySymlink(link, developer_path);
}

std::string SymlinkedInterfacePath(
    std::string_view interface_path,
    std::function<std::string()> developer_dir_supplier) {
  std::filesystem::path source{std::string(interface_path)};
  // Relative swiftinterface paths will be recorded relatively, so we don't need
  // workarounds
  if (!source.is_absolute()) {
    return source.string();
  }

  std::string developer_dir = NormalizeDeveloperDir(developer_dir_supplier());
  if (developer_dir.empty()) {
    std::cerr << "error: DEVELOPER_DIR is not set, but is required to "
                 "compile Swift interfaces with absolute paths\n";
    std::exit(EXIT_FAILURE);
  }

  std::filesystem::path developer_path{developer_dir};
  auto relative_to_developer = source.lexically_relative(developer_path);
  if (relative_to_developer.empty()) {
    std::cerr << "error: absolute path " << source
              << " is not within DEVELOPER_DIR " << developer_path
              << ", which is required to compile Swift interfaces with "
                 "absolute paths\n";
    std::exit(EXIT_FAILURE);
  }

  if (!EnsureDeveloperDirSymlink(developer_dir)) {
    std::exit(EXIT_FAILURE);
  }

  return (std::filesystem::path(DeveloperDirSymlinkName()) /
          relative_to_developer)
      .string();
}

}  // namespace bazel_rules_swift
