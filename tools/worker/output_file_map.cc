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

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

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

// Returns the extension of the per-file output of the given kind, matching the
// names that `_declare_per_source_output_file` declares for regular sources, or
// an empty string for an unknown kind.
static std::string ExtensionForKind(const std::string& kind,
                                    const nlohmann::json& outputs) {
  if (kind == "object") return "o";
  if (kind == "llvm-bc") return "bc";
  if (kind == "ast-dump") return "ast";
  if (kind == "const-values") return "swiftconstvalues";
  if (kind == "swift-dependencies") return "swiftdeps";
  if (kind == "index-unit-output-path") {
    return outputs.contains("llvm-bc") ? "bc" : "o";
  }
  return "";
}

// Returns whether an action with the given outputs writes the outputs of the
// given kind to the declared output directories.
static bool ActionWritesKind(OutputFileMap::ActionOutputs action_outputs,
                             const std::string& kind) {
  switch (action_outputs) {
    case OutputFileMap::ActionOutputs::kCompile:
      return kind == "object" || kind == "llvm-bc" || kind == "const-values";
    case OutputFileMap::ActionOutputs::kDumpAst:
      return kind == "ast-dump";
  }
  return false;
}

// Replaces entries whose key is a directory (a tree artifact in `srcs`) with
// one entry per Swift file under it. The analysis phase can't see the files in
// a tree artifact, so the values of a directory's entry name output directories
// instead of files; each Swift file's outputs go to the same relative path
// inside them. Returns false and sets `error` on failure.
static bool ExpandSourceDirectories(nlohmann::json& json,
                                    OutputFileMap::ActionOutputs action_outputs,
                                    std::string* error) {
  nlohmann::json expanded = nlohmann::json::object();

  for (auto& element : json.items()) {
    const std::string& src = element.key();
    const nlohmann::json& outputs = element.value();
    std::error_code ec;
    if (src.empty() || !std::filesystem::is_directory(src, ec)) {
      expanded[src] = outputs;
      continue;
    }

    std::vector<std::string> relative_paths;
    if (!OutputFileMap::ListSourceDirectory(src, &relative_paths, error)) {
      return false;
    }

    for (const auto& relative_path : relative_paths) {
      nlohmann::json file_outputs;
      for (auto& output : outputs.items()) {
        auto kind = output.key();
        auto extension = ExtensionForKind(kind, outputs);
        if (extension.empty()) {
          *error =
              "Unknown output kind '" + kind + "' for source directory " + src;
          return false;
        }
        auto path = std::filesystem::path(output.value().get<std::string>()) /
                    (relative_path + "." + extension);
        // Bazel creates the declared output directories, but not the
        // subdirectories that mirror the source directory's layout.
        if (ActionWritesKind(action_outputs, kind)) {
          std::filesystem::create_directories(path.parent_path(), ec);
          if (ec) {
            *error = "Could not create directory " +
                     path.parent_path().string() + " (" + ec.message() + ")";
            return false;
          }
        }
        file_outputs[kind] = path.generic_string();
      }
      // Keys must match the paths Bazel passes on the command line.
      expanded[src + "/" + relative_path] = file_outputs;
    }
  }

  json = expanded;
  return true;
}

};  // end namespace

bool OutputFileMap::ListSourceDirectory(
    const std::string& directory, std::vector<std::string>* relative_paths,
    std::string* error) {
  std::error_code ec;
  std::filesystem::recursive_directory_iterator it(
      directory, std::filesystem::directory_options::follow_directory_symlink,
      ec);
  for (; !ec && it != std::filesystem::recursive_directory_iterator();
       it.increment(ec)) {
    if (it->is_regular_file() && it->path().extension() == ".swift") {
      // Sources in a directory may be symlinks, so the path must not be
      // resolved.
      relative_paths->push_back(
          it->path().lexically_relative(directory).generic_string());
    }
  }
  if (ec) {
    *error = "Could not list source directory " + directory + " (" +
             ec.message() + ")";
    return false;
  }
  std::sort(relative_paths->begin(), relative_paths->end());
  return true;
}

bool OutputFileMap::ReadFromPath(const std::string& path,
                                 const std::string& emit_module_path,
                                 const std::string& emit_objc_header_path,
                                 bool expand_source_directories) {
  std::ifstream stream(path);
  stream >> json_;
  if (expand_source_directories &&
      !ExpandSourceDirectories(json_, ActionOutputs::kCompile, &error_)) {
    return false;
  }
  UpdateForIncremental(path, emit_module_path, emit_objc_header_path);
  return true;
}

void OutputFileMap::WriteToPath(const std::string& path) {
  std::ofstream stream(path);
  stream << json_;
}

bool OutputFileMap::WriteExpanded(const std::string& path,
                                  const std::string& expanded_path,
                                  ActionOutputs action_outputs,
                                  std::string* error) {
  nlohmann::json json;
  {
    std::ifstream stream(path);
    json = nlohmann::json::parse(stream, /*cb=*/nullptr,
                                 /*allow_exceptions=*/false);
  }
  if (json.is_discarded()) {
    *error = "Could not parse output file map " + path;
    return false;
  }
  if (!ExpandSourceDirectories(json, action_outputs, error)) {
    return false;
  }
  std::ofstream stream(expanded_path);
  stream << json;
  stream.close();
  if (!stream) {
    *error = "Could not write output file map " + expanded_path;
    return false;
  }
  return true;
}

void OutputFileMap::UpdateForIncremental(
    const std::string& path, const std::string& emit_module_path,
    const std::string& emit_objc_header_path) {
  bool derived =
      path.find(".derived_output_file_map.json") != std::string::npos;

  nlohmann::json new_output_file_map;
  std::map<std::string, std::string> incremental_outputs;
  std::map<std::string, std::string> incremental_inputs;
  std::vector<std::string> incremental_cleanup_outputs;

  // The empty string key is used to represent outputs that are for the whole
  // module, rather than for a particular source file.
  nlohmann::json module_map;
  // Derive the swiftdeps file name from the .output-file-map.json name.
  std::string new_path =
      std::filesystem::path(path).replace_extension(".swiftdeps").string();
  auto swiftdeps_path = MakeIncrementalOutputPath(new_path, derived);
  module_map["swift-dependencies"] = swiftdeps_path;
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
        auto new_path = MakeIncrementalOutputPath(path, derived);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;

        if (swiftdeps_path.empty()) {
          swiftdeps_path = std::filesystem::path(new_path)
                               .replace_extension(".swiftdeps")
                               .string();
        }

        incremental_cleanup_outputs.push_back(swiftdeps_path);
      } else if (kind == "swiftdoc" || kind == "swiftinterface" ||
                 kind == "swiftmodule" || kind == "swiftsourceinfo") {
        // Module/interface outputs should be moved to the incremental storage
        // area without additional processing.
        auto new_path = MakeIncrementalOutputPath(path, derived);
        src_map[kind] = new_path;
        incremental_outputs[path] = new_path;

        if (swiftdeps_path.empty()) {
          swiftdeps_path = std::filesystem::path(new_path)
                               .replace_extension(".swiftdeps")
                               .string();
        }

        incremental_cleanup_outputs.push_back(swiftdeps_path);
      } else if (kind == "swift-dependencies") {
        // Only derived-file maps need explicit per-source dependency paths.
        // So we ignore other entries, including those added by a previous
        // rewrite.
        if (derived && !src.empty()) {
          swiftdeps_path = MakeIncrementalOutputPath(path, derived);
          incremental_cleanup_outputs.push_back(swiftdeps_path);

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

  // If we don't generate a swiftmodule, don't try to copy those files
  if (!emit_module_path.empty()) {
    auto swiftmodule_path = emit_module_path;
    auto copied_swiftmodule_path =
        MakeIncrementalOutputPath(swiftmodule_path, derived);
    incremental_inputs[swiftmodule_path] = copied_swiftmodule_path;

    std::string swiftdoc_path = std::filesystem::path(swiftmodule_path)
                                    .replace_extension(".swiftdoc")
                                    .string();
    auto copied_swiftdoc_path =
        MakeIncrementalOutputPath(swiftdoc_path, derived);
    incremental_inputs[swiftdoc_path] = copied_swiftdoc_path;
  }

  if (!emit_objc_header_path.empty()) {
    auto copied_objc_header_path =
        MakeIncrementalOutputPath(emit_objc_header_path, derived);
    incremental_inputs[emit_objc_header_path] = copied_objc_header_path;
  }

  json_ = new_output_file_map;
  incremental_outputs_ = incremental_outputs;
  incremental_inputs_ = incremental_inputs;
  incremental_cleanup_outputs_ = incremental_cleanup_outputs;
}
