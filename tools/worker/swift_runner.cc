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

#include "tools/worker/swift_runner.h"

#include <filesystem>
#include <fstream>
#include <optional>
#include <sstream>
#include <utility>

#include "absl/strings/match.h"
#include "absl/strings/string_view.h"
#include "absl/strings/strip.h"
#include "absl/strings/substitute.h"
#include "tools/common/bazel_substitutions.h"
#include "tools/common/file_system.h"
#include "tools/common/process.h"
#include "tools/common/target_triple.h"
#include "tools/common/temp_file.h"
#include "tools/worker/output_file_map.h"
#include "tools/worker/pcm_hermetic_runner.h"

bool ArgumentEnablesWMO(const std::string &arg) {
  return arg == "-wmo" || arg == "-whole-module-optimization" ||
         arg == "-force-single-frontend-invocation";
}

namespace {

using bazel_rules_swift::PathExists;
using bazel_rules_swift::TargetTriple;

// Creates a temporary file and writes the given arguments to it, one per line.
static std::unique_ptr<TempFile> WriteResponseFile(
    const std::vector<std::string> &args) {
  auto response_file = TempFile::Create("swiftc_params.XXXXXX");
  std::ofstream response_file_stream(response_file->GetPath());

  for (const auto &arg : args) {
    // When Clang/Swift write out a response file to communicate from driver to
    // frontend, they just quote every argument to be safe; we duplicate that
    // instead of trying to be "smarter" and only quoting when necessary.
    response_file_stream << '"';
    for (auto ch : arg) {
      if (ch == '"' || ch == '\\') {
        response_file_stream << '\\';
      }
      response_file_stream << ch;
    }
    response_file_stream << "\"\n";
  }

  response_file_stream.close();
  return response_file;
}

// Unescape and unquote an argument read from a line of a response file.
static std::string Unescape(const std::string &arg) {
  std::string result;
  auto length = arg.size();
  for (size_t i = 0; i < length; ++i) {
    auto ch = arg[i];

    // If it's a backslash, consume it and append the character that follows.
    if (ch == '\\' && i + 1 < length) {
      ++i;
      result.push_back(arg[i]);
      continue;
    }

    // If it's a quote, process everything up to the matching quote, unescaping
    // backslashed characters as needed.
    if (ch == '"' || ch == '\'') {
      auto quote = ch;
      ++i;
      while (i != length && arg[i] != quote) {
        if (arg[i] == '\\' && i + 1 < length) {
          ++i;
        }
        result.push_back(arg[i]);
        ++i;
      }
      if (i == length) {
        break;
      }
      continue;
    }

    // It's a regular character.
    result.push_back(ch);
  }

  return result;
}

// Consumes and returns a single argument from the given command line (skipping
// any leading whitespace and also handling quoted/escaped arguments), advancing
// the view to the end of the argument in a similar fashion to
// `absl::ConsumePrefix()`.
static std::optional<std::string> ConsumeArg(absl::string_view *line) {
  size_t whitespace_count = 0;
  size_t length = line->size();
  while (whitespace_count < length && (*line)[whitespace_count] == ' ') {
    whitespace_count++;
  }
  if (whitespace_count > 0) {
    line->remove_prefix(whitespace_count);
  }

  if (line->empty()) {
    return std::nullopt;
  }

  std::string result;
  length = line->size();
  size_t i = 0;
  for (i = 0; i < length; ++i) {
    char ch = (*line)[i];

    if (ch == ' ') {
      break;
    }

    // If it's a backslash, consume it and append the character that follows.
    if (ch == '\\' && i + 1 < length) {
      ++i;
      result.push_back((*line)[i]);
      continue;
    }

    // If it's a quote, process everything up to the matching quote, unescaping
    // backslashed characters as needed.
    if (ch == '"' || ch == '\'') {
      char quote = ch;
      ++i;
      while (i != length && (*line)[i] != quote) {
        if ((*line)[i] == '\\' && i + 1 < length) {
          ++i;
        }
        result.push_back((*line)[i]);
        ++i;
      }
      if (i == length) {
        break;
      }
      continue;
    }

    // It's a regular character.
    result.push_back(ch);
  }

  line->remove_prefix(i);
  return result;
}

// If `str` starts with `prefix`, `str` is mutated to remove `prefix` and the
// function returns true. Otherwise, `str` is left unmodified and the function
// returns `false`.
static bool StripPrefix(const std::string &prefix, std::string &str) {
  if (str.find(prefix) != 0) {
    return false;
  }
  str.erase(0, prefix.size());
  return true;
}

// Infers the path to the `.swiftinterface` file inside a `.swiftmodule`
// directory based on the given target triple.
//
// This roughly mirrors the logic in the Swift frontend's
// `forEachTargetModuleBasename` function at
// https://github.com/swiftlang/swift/blob/d36b06747a54689a09ca6771b04798fc42b3e701/lib/Serialization/SerializedModuleLoader.cpp#L55.
std::optional<std::string> InferInterfacePath(
    absl::string_view module_path, absl::string_view target_triple_string) {
  std::optional<TargetTriple> parsed_triple =
      TargetTriple::Parse(target_triple_string);
  if (!parsed_triple.has_value()) {
    return std::nullopt;
  }

  // The target triple passed to us by the build rules has already been
  // normalized (e.g., `macos` instead of `macosx`), so we don't have to do as
  // much work here as the frontend normally would.
  TargetTriple normalized_triple = parsed_triple->WithoutOSVersion();

  // First, try the triple we were given.
  std::string attempt = absl::Substitute("$0/$1.swiftinterface", module_path,
                                         normalized_triple.TripleString());
  if (PathExists(attempt)) {
    return attempt;
  }

  // Next, if the target triple is `arm64`, we can also load an `arm64e`
  // interface, so try that.
  if (normalized_triple.Arch() == "arm64") {
    TargetTriple arm64e_triple = normalized_triple.WithArch("arm64e");
    attempt = absl::Substitute("$0/$1.swiftinterface", module_path,
                               arm64e_triple.TripleString());
    if (PathExists(attempt)) {
      return attempt;
    }
  }

  return std::nullopt;
}

// Extracts flags from the given `.swiftinterface` file and passes them to the
// given consumer.
void ExtractFlagsFromInterfaceFile(
    absl::string_view module_or_interface_path, absl::string_view target_triple,
    std::function<void(absl::string_view)> consumer) {
  std::string interface_path;
  if (absl::EndsWith(module_or_interface_path, ".swiftinterface")) {
    interface_path = std::string(module_or_interface_path);
  } else {
    std::optional<std::string> inferred_path =
        InferInterfacePath(module_or_interface_path, target_triple);
    if (!inferred_path.has_value()) {
      return;
    }
    interface_path = *inferred_path;
  }

  // Add the path to the interface file as a source file argument, then extract
  // the flags from it and add them as well.
  consumer(interface_path);

  std::ifstream interface_file{std::string(interface_path)};
  std::string line;
  while (std::getline(interface_file, line)) {
    absl::string_view line_view = line;
    if (absl::ConsumePrefix(&line_view, "// swift-module-flags: ")) {
      bool skip_next = false;
      while (std::optional<std::string> flag = ConsumeArg(&line_view)) {
        if (skip_next) {
          skip_next = false;
        } else if (*flag == "-target") {
          // We have to skip the target triple in the interface file because it
          // might be slightly different from the one the rest of our
          // dependencies were compiled with. For example, if we are targeting
          // `arm64-apple-macos`, that is the architecture that any Clang
          // module dependencies will have used. If the module uses
          // `arm64e-apple-macos` instead, then it will not be compatible with
          // those Clang modules.
          skip_next = true;
        } else {
          consumer(*flag);
        }
      }
      return;
    }
  }
}

}  // namespace

SwiftRunner::SwiftRunner(const std::vector<std::string> &args,
                         std::string index_import_path, bool force_response_file)
    : job_env_(GetCurrentEnvironment()),
      index_import_path_(index_import_path),
      force_response_file_(force_response_file),
      is_dump_ast_(false),
      file_prefix_pwd_is_dot_(false),
      hermetic_pcm_(false) {
  args_ = ProcessArguments(args);
}

int SwiftRunner::Run(std::ostream *stderr_stream, bool stdout_to_stderr) {
  // In rules_swift < 3.x the .swiftsourceinfo files are unconditionally written to the module path.
  // In rules_swift >= 3.x these same files are no longer tracked by Bazel unless explicitly requested.
  // When using non-sandboxed mode, previous builds will contain these files and cause build failures
  // when Swift tries to use them, in order to work around this compatibility issue, we check the module path for
  // the presence of .swiftsourceinfo files and if they are present but not requested, we remove them.
  if (swift_source_info_path_ != "" && !emit_swift_source_info_) {
    std::filesystem::remove(swift_source_info_path_);
  }

  int exit_code =
      hermetic_pcm_
          ? RunHermeticPcm(args_, stderr_stream)
          : RunSubProcess(args_, &job_env_, stderr_stream, stdout_to_stderr);

  if (exit_code != 0) {
    return exit_code;
  }

  if (!generated_header_rewriter_path_.empty()) {
#if __APPLE__
    // Skip the `xcrun` argument that's added when running on Apple platforms.
    int initial_args_to_skip = 1;
#else
    int initial_args_to_skip = 0;
#endif

    std::vector<std::string> rewriter_args;
    rewriter_args.reserve(args_.size() + 2 - initial_args_to_skip);
    rewriter_args.push_back(generated_header_rewriter_path_);
    rewriter_args.push_back("--");
    rewriter_args.insert(rewriter_args.end(),
                         args_.begin() + initial_args_to_skip, args_.end());

    exit_code = RunSubProcess(
        rewriter_args, /*env=*/nullptr, stderr_stream, stdout_to_stderr);
  }

  auto enable_global_index_store = global_index_store_import_path_ != "";
  if (enable_global_index_store) {
    if (index_import_path_.empty()) {
      (*stderr_stream) << "Failed to find index-import path from runfiles\n";
      return EXIT_FAILURE;
    }

    OutputFileMap output_file_map;
    output_file_map.ReadFromPath(output_file_map_path_, "", "");

    auto outputs = output_file_map.incremental_outputs();
    std::map<std::string, std::string>::iterator it;

    std::vector<std::string> ii_args;
    ii_args.push_back(index_import_path_);

    if (file_prefix_pwd_is_dot_) {
      ii_args.push_back("-file-prefix-map");
      ii_args.push_back(std::filesystem::current_path().string() + "=.");
    }

    for (it = outputs.begin(); it != outputs.end(); it++) {
      // Need the actual output paths of the compiler - not bazel
      auto output_path = it->first;
      auto file_type = output_path.substr(output_path.find_last_of(".") + 1);
      if (file_type == "o") {
        ii_args.push_back("-import-output-file");
        ii_args.push_back(output_path);
      }
    }

    const std::filesystem::path &exec_root = std::filesystem::current_path();
    // Copy back from the global index store to bazel's index store
    ii_args.push_back((exec_root / global_index_store_import_path_).string());
    ii_args.push_back((exec_root / index_store_path_).string());
    exit_code = RunSubProcess(
        ii_args, /*env=*/nullptr, stderr_stream, /*stdout_to_stderr=*/true);
  }
  return exit_code;
}

// Marker for end of iteration
class StreamIteratorEnd {};

// Basic iterator over an ifstream
class StreamIterator {
 public:
  StreamIterator(std::ifstream &file) : file_{file} { next(); }

  const std::string &operator*() const { return str_; }

  StreamIterator &operator++() {
    next();
    return *this;
  }

  bool operator!=(StreamIteratorEnd) const { return !!file_; }

 private:
  void next() { std::getline(file_, str_); }

  std::ifstream &file_;
  std::string str_;
};

class ArgsFile {
 public:
  ArgsFile(std::ifstream &file) : file_(file) {}

  StreamIterator begin() { return StreamIterator{file_}; }

  StreamIteratorEnd end() { return StreamIteratorEnd{}; }

 private:
  std::ifstream &file_;
};

bool SwiftRunner::ProcessPossibleResponseFile(
    const std::string &arg, std::function<void(const std::string &)> consumer) {
  auto path = arg.substr(1);
  std::ifstream original_file(path);
  ArgsFile args_file(original_file);

  // If we couldn't open it, maybe it's not a file; maybe it's just some other
  // argument that starts with "@" such as "@loader_path/..."
  if (!original_file.good()) {
    consumer(arg);
    return false;
  }

  // Read the file to a vector to prevent double I/O
  auto args = ParseArguments(args_file);

  // If we're forcing response files, process and send the arguments from this
  // file directly to the consumer; they'll all get written to the same response
  // file at the end of processing all the arguments.
  if (force_response_file_) {
    for (auto it = args.begin(); it != args.end(); ++it) {
      // Arguments in response files might be quoted/escaped, so we need to
      // unescape them ourselves.
      ProcessArgument(it, Unescape(*it), consumer);
    }
    return true;
  }

  // Otherwise, open the file, process the arguments, and rewrite it if any of
  // them have changed.
  bool changed = false;
  std::string arg_from_file;
  std::vector<std::string> new_args;
  for (auto it = args.begin(); it != args.end(); ++it) {
    changed |= ProcessArgument(it, *it, [&](const std::string &processed_arg) {
      new_args.push_back(processed_arg);
    });
  }

  if (changed) {
    auto new_file = WriteResponseFile(new_args);
    consumer("@" + new_file->GetPath());
    temp_files_.push_back(std::move(new_file));
  } else {
    // If none of the arguments changed, just keep the original response file
    // argument.
    consumer(arg);
  }

  return changed;
}

std::string SwiftRunner::ProcessExplicitSwiftModuleMapFile(
    const std::string &path) {
  std::string module_map_path = path;
  std::ifstream module_map_file(module_map_path);
  if (!module_map_file.good()) {
    return module_map_path;
  }

  std::stringstream buffer;
  buffer << module_map_file.rdbuf();
  std::string contents = buffer.str();
  bazel_placeholder_substitutions_.Apply(contents);

  auto rewritten_module_map =
      TempFile::Create("swift_explicit_module_map.XXXXXX");
  std::ofstream rewritten_module_map_stream(rewritten_module_map->GetPath());
  rewritten_module_map_stream << contents;
  rewritten_module_map_stream.close();

  module_map_path = rewritten_module_map->GetPath();
  temp_files_.push_back(std::move(rewritten_module_map));
  return module_map_path;
}

template <typename Iterator>
bool SwiftRunner::ProcessArgument(
    Iterator &itr, const std::string &arg,
    std::function<void(const std::string &)> consumer) {
  bool changed = false;

  // Helper function for adding path remapping flags that depend on information
  // only known at execution time.
  auto add_prefix_map_flags = [&](const std::string &flag,
                                  const std::string &new_path = ".") {
    // Get the actual current working directory (the execution root), which
    // we didn't know at analysis time.
    consumer(flag);
    consumer(std::filesystem::current_path().string() + "=" + new_path);

#if __APPLE__
    std::string developer_dir = "__BAZEL_XCODE_DEVELOPER_DIR__";
    if (bazel_placeholder_substitutions_.Apply(developer_dir)) {
      consumer(flag);
      consumer(developer_dir + "=/PLACEHOLDER_DEVELOPER_DIR");
    }
#endif
  };

  if (arg[0] == '@') {
    changed = ProcessPossibleResponseFile(arg, consumer);
  } else {
    std::string new_arg = arg;
    if (StripPrefix("-Xwrapped-swift=", new_arg)) {
      if (new_arg == "-debug-prefix-pwd-is-dot") {
        // Replace the $PWD with . to make the paths relative to the workspace
        // without breaking hermiticity.
        add_prefix_map_flags("-debug-prefix-map");
        changed = true;
      } else if (new_arg == "-coverage-prefix-pwd-is-dot") {
        // Replace the $PWD with . to make the paths relative to the workspace
        // without breaking hermiticity.
        add_prefix_map_flags("-coverage-prefix-map");
        changed = true;
      } else if (new_arg == "-coverage-prefix-pwd-is-canonical") {
        // Replace the $PWD with the canonical (resolved) path to the source root.
        // The bazel execroot is a normal directory, but inside of it there are
        // symlinks to our source tree. This fetches the true path of a known
        // directory in order to get the actual source root of the project. This
        // should only work with sandboxing disabled.
        auto cwd = std::filesystem::current_path();
        auto target_path = std::filesystem::canonical(cwd / "BUILD.bazel").parent_path();
        add_prefix_map_flags("-coverage-prefix-map", target_path.string());
        changed = true;
      } else if (new_arg == "-file-prefix-pwd-is-dot") {
        // Replace the $PWD with . to make the paths relative to the workspace
        // without breaking hermiticity.
        add_prefix_map_flags("-file-prefix-map");
        changed = true;
      } else if (StripPrefix("-macro-expansion-dir=", new_arg)) {
        changed = true;
        std::filesystem::create_directories(new_arg);
#if __APPLE__
        job_env_["TMPDIR"] = new_arg;
#else
        // TEMPDIR is read by C++ but not Swift. Swift requires the temprorary
        // directory to be an absolute path and otherwise fails (or ignores it
        // silently on macOS) so we need to set one that Swift does not read.
        // C++ prioritizes TMPDIR over TEMPDIR so we need to wipe out the other
        // one. The downside is that anything else reading TMPDIR will not use
        // the one potentially set by the user.
        job_env_["TEMPDIR"] = new_arg;
        job_env_.erase("TMPDIR");
#endif
      } else if (new_arg == "-ephemeral-module-cache") {
        // Create a temporary directory to hold the module cache, which will be
        // deleted after compilation is finished.
        auto module_cache_dir =
            TempDirectory::Create("swift_module_cache.XXXXXX");
        consumer("-module-cache-path");
        consumer(module_cache_dir->GetPath());
        temp_directories_.push_back(std::move(module_cache_dir));
        changed = true;
      } else if (StripPrefix("-generated-header-rewriter=", new_arg)) {
        changed = true;
      } else if (StripPrefix("-bazel-target-label=", new_arg)) {
        changed = true;
      } else if (StripPrefix("-global-index-store-import-path=", new_arg)) {
        changed = true;
      } else if (new_arg == "-hermetic-pcm") {
        changed = true;
      } else if (StripPrefix(
                     "-explicit-compile-module-from-interface=", new_arg)) {
        module_or_interface_path_ = new_arg;
        bazel_placeholder_substitutions_.Apply(module_or_interface_path_);
        changed = true;
      } else if (StripPrefix(
                     "-driver-explicit-swift-module-map-file=", new_arg)) {
        consumer("-Xfrontend");
        consumer("-explicit-swift-module-map-file");
        consumer("-Xfrontend");
        consumer(ProcessExplicitSwiftModuleMapFile(new_arg));
        changed = true;
      } else if (StripPrefix(
                     "-frontend-explicit-swift-module-map-file=", new_arg)) {
        consumer("-explicit-swift-module-map-file");
        consumer(ProcessExplicitSwiftModuleMapFile(new_arg));
        changed = true;
      } else {
        // TODO(allevato): Report that an unknown wrapper arg was found and give
        // the caller a way to exit gracefully.
        changed = true;
      }
    } else {
      // Process default arguments
      if (arg == "-index-store-path") {
        consumer("-index-store-path");
        ++itr;

        // If there was a global index store set, pass that to swiftc.
        // Otherwise, pass the users. We later copy index data onto the users.
        if (global_index_store_import_path_ != "") {
          new_arg = global_index_store_import_path_;
        } else {
          new_arg = index_store_path_;
        }
        changed = true;
      } else if (arg == "-output-file-map") {
        // Save the output file map to the value proceeding
        // `-output-file-map`
        consumer("-output-file-map");
        ++itr;
        new_arg = output_file_map_path_;
        changed = true;
      } else if (arg == "-target") {
        consumer("-target");
        ++itr;
        new_arg = *itr;
        target_triple_ = new_arg;
      } else if (is_dump_ast_ && ArgumentEnablesWMO(arg)) {
        // WMO is invalid for -dump-ast,
        // so omit the argument that enables WMO
        return true;  // return to avoid consuming the arg
      }

      // Apply any other text substitutions needed in the argument (i.e., for
      // Apple toolchains).
      //
      // Bazel doesn't quote arguments in multi-line params files, so we need
      // to ensure that our defensive quoting kicks in if an argument contains
      // a space, even if no other changes would have been made.
      changed = bazel_placeholder_substitutions_.Apply(new_arg) ||
                changed || new_arg.find_first_of(' ') != std::string::npos;
      consumer(new_arg);
    }
  }

  return changed;
}

template <typename Iterator>
std::vector<std::string> SwiftRunner::ParseArguments(Iterator itr) {
  std::vector<std::string> out_args;
  for (auto it = itr.begin(); it != itr.end(); ++it) {
    auto arg = *it;
    out_args.push_back(arg);

    if (StripPrefix("-Xwrapped-swift=", arg)) {
      if (StripPrefix("-global-index-store-import-path=", arg)) {
        global_index_store_import_path_ = arg;
      } else if (StripPrefix("-generated-header-rewriter=", arg)) {
        generated_header_rewriter_path_ = arg;
      } else if (StripPrefix("-bazel-target-label=", arg)) {
        target_label_ = arg;
      } else if (arg == "-file-prefix-pwd-is-dot") {
        file_prefix_pwd_is_dot_ = true;
      } else if (arg == "-emit-swiftsourceinfo") {
        emit_swift_source_info_ = true;
      } else if (arg == "-hermetic-pcm") {
        hermetic_pcm_ = true;
      } else if (StripPrefix(
                     "-explicit-compile-module-from-interface=", arg)) {
        module_or_interface_path_ = arg;
      }
    } else {
      if (arg == "-output-file-map") {
        ++it;
        arg = *it;
        output_file_map_path_ = arg;
        out_args.push_back(arg);
      } else if (arg == "-index-store-path") {
        ++it;
        arg = *it;
        index_store_path_ = arg;
        out_args.push_back(arg);
      } else if (arg == "-dump-ast") {
        is_dump_ast_ = true;
      } else if (arg == "-emit-module-path") {
        ++it;
        arg = *it;
        std::filesystem::path module_path(arg);
        swift_source_info_path_ = module_path.replace_extension(".swiftsourceinfo").string();
        out_args.push_back(arg);
      } else if (arg == "-target") {
        ++it;
        arg = *it;
        target_triple_ = arg;
        out_args.push_back(arg);
      }
    }
  }
  return out_args;
}

std::vector<std::string> SwiftRunner::ProcessArguments(
    const std::vector<std::string> &args) {
  std::vector<std::string> new_args;
  std::vector<std::string> response_file_args;

#if __APPLE__
  // On Apple platforms, inject `/usr/bin/xcrun` in front of our command
  // invocation.
  new_args.push_back("/usr/bin/xcrun");
#endif

  // The tool is assumed to be the first argument. Push it directly.
  auto parsed_args = ParseArguments(args);

  auto it = parsed_args.begin();
  new_args.push_back(*it++);

  // If we're forcing response files, push the remaining processed args onto a
  // different vector that we write out below. If not, push them directly onto
  // the vector being returned.
  auto &args_destination = force_response_file_ ? response_file_args : new_args;
  while (it != parsed_args.end()) {
    ProcessArgument(it, *it, [&](const std::string &arg) {
      args_destination.push_back(arg);
    });
    ++it;
  }

  if (!module_or_interface_path_.empty()) {
    ExtractFlagsFromInterfaceFile(
        module_or_interface_path_, target_triple_,
        [&](absl::string_view arg) {
          args_destination.push_back(std::string(arg));
        });
  }

  if (force_response_file_) {
    // Write the processed args to the response file, and push the path to that
    // file (preceded by '@') onto the arg list being returned.
    auto new_file = WriteResponseFile(response_file_args);
    new_args.push_back("@" + new_file->GetPath());
    temp_files_.push_back(std::move(new_file));
  }

  return new_args;
}
