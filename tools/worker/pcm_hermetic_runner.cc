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

#include "tools/worker/pcm_hermetic_runner.h"

#include <cstdlib>
#include <filesystem>
#include <sstream>
#include <string>
#include <vector>

#include "tools/common/process.h"

namespace {

constexpr const char* kDebugEnv = "RULES_SWIFT_HERMETIC_PCM_DEBUG";
constexpr const char* kDeveloperDirSymlinkName = "__bazel_pcm_developer_dir";
constexpr const char* kResourceDirSymlinkName = "__bazel_pcm_resource_dir";
constexpr const char* kSdkSymlinkName = "__bazel_pcm_sdk";

bool ShouldDropFlagAndValue(const std::string& arg) {
  return arg == "-external-plugin-path" ||
         arg == "-in-process-plugin-server-path" || arg == "-plugin-path";
}

std::string GetEnv(const char* name) {
  const char* value = std::getenv(name);
  return (value != nullptr && value[0] != '\0') ? std::string(value)
                                                : std::string();
}

void ReplaceAll(std::string& arg, const std::string& needle,
                const std::string& replacement) {
  if (needle.empty()) return;
  size_t pos = 0;
  while ((pos = arg.find(needle, pos)) != std::string::npos) {
    arg.replace(pos, needle.size(), replacement);
    pos += replacement.size();
  }
}

int CaptureFrontendCommand(const std::vector<std::string>& args,
                           std::ostream* stderr_stream, std::string* captured) {
  std::vector<std::string> driver_args = args;
  driver_args.push_back("-###");

  std::stringstream sink;
  int rc = RunSubProcess(driver_args, /*env=*/nullptr, &sink,
                         /*stdout_to_stderr=*/true);
  *captured = sink.str();
  if (rc != 0) {
    (*stderr_stream) << "hermetic-pcm: swiftc -### exited " << rc << ":\n"
                     << *captured;
  }
  return rc;
}

std::vector<std::string> TokenizeShellLine(const std::string& line) {
  std::vector<std::string> tokens;
  std::string token;
  bool in_quotes = false;
  for (size_t i = 0; i < line.size(); ++i) {
    char c = line[i];
    if (c == '\\' && i + 1 < line.size()) {
      token.push_back(line[i + 1]);
      ++i;
      continue;
    }
    if (c == '"') {
      in_quotes = !in_quotes;
      continue;
    }
    if (!in_quotes && (c == ' ' || c == '\t')) {
      if (!token.empty()) {
        tokens.push_back(std::move(token));
        token.clear();
      }
      continue;
    }
    token.push_back(c);
  }
  if (!token.empty()) {
    tokens.push_back(std::move(token));
  }
  return tokens;
}

std::vector<std::string> ParseFrontendCommand(const std::string& output) {
  std::string line;
  std::string last_line;
  std::istringstream iss(output);
  while (std::getline(iss, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    if (!line.empty()) {
      last_line = line;
    }
  }
  if (last_line.empty()) {
    return {};
  }
  return TokenizeShellLine(last_line);
}

bool Symlink(const std::string& target, const std::string& link_name,
             std::ostream* stderr_stream) {
  std::filesystem::path link = std::filesystem::current_path() / link_name;
  std::error_code ec;
  std::filesystem::remove(link, ec);
  std::filesystem::create_directory_symlink(target, link, ec);
  if (ec) {
    (*stderr_stream) << "hermetic-pcm: failed to symlink " << target << " -> "
                     << link << ": " << ec.message() << "\n";
    return false;
  }
  return true;
}

std::string ResourceDirFromFrontend(const std::string& frontend_binary) {
  if (frontend_binary.empty()) return {};
  std::filesystem::path p(frontend_binary);
  // .../usr/bin/swift-frontend -> .../usr -> .../usr/lib/swift
  auto usr = p.parent_path().parent_path();
  if (usr.empty()) return {};
  return (usr / "lib" / "swift").string();
}

}  // namespace

int RunHermeticPcm(const std::vector<std::string>& args,
                   std::ostream* stderr_stream) {
  const std::string developer_dir = GetEnv("DEVELOPER_DIR");
  if (developer_dir.empty()) {
    (*stderr_stream) << "hermetic-pcm: DEVELOPER_DIR is not set\n";
    return 1;
  }

  const std::string sdk_path = GetEnv("SDKROOT");
  if (sdk_path.empty()) {
    (*stderr_stream) << "hermetic-pcm: SDKROOT is not set\n";
    return 1;
  }

  std::string captured;
  int rc = CaptureFrontendCommand(args, stderr_stream, &captured);
  if (rc != 0) {
    return rc;
  }

  std::vector<std::string> frontend = ParseFrontendCommand(captured);
  if (frontend.empty()) {
    (*stderr_stream) << "hermetic-pcm: could not parse frontend command from:\n"
                     << captured;
    return 1;
  }

  const std::string resource_dir = ResourceDirFromFrontend(frontend[0]);
  if (resource_dir.empty()) {
    return 1;
  }
  if (!Symlink(sdk_path, kSdkSymlinkName, stderr_stream)) {
    return 1;
  }
  if (!Symlink(resource_dir, kResourceDirSymlinkName, stderr_stream)) {
    return 1;
  }
  if (!Symlink(developer_dir, kDeveloperDirSymlinkName, stderr_stream)) {
    return 1;
  }

  std::vector<std::string> rewritten;
  rewritten.reserve(frontend.size() + 2);
  for (size_t i = 0; i < frontend.size(); ++i) {
    const std::string& arg = frontend[i];
    if (ShouldDropFlagAndValue(arg)) {
      ++i;
      continue;
    }
    std::string rewritten_arg = arg;
    ReplaceAll(rewritten_arg, sdk_path, kSdkSymlinkName);
    ReplaceAll(rewritten_arg, developer_dir, kDeveloperDirSymlinkName);
    rewritten.push_back(std::move(rewritten_arg));
  }

  // The frontend otherwise auto-derives the resource dir from argv[0],
  // which is an absolute path into Xcode. It needs to be relative.
  rewritten.push_back("-resource-dir");
  rewritten.push_back(kResourceDirSymlinkName);

  if (!GetEnv(kDebugEnv).empty()) {
    (*stderr_stream) << "hermetic-pcm: sdk_path='" << sdk_path << "'\n";
    (*stderr_stream) << "hermetic-pcm: running";
    for (const std::string& arg : rewritten) {
      (*stderr_stream) << ' ' << arg;
    }
    (*stderr_stream) << '\n';
  }

  return RunSubProcess(rewritten, /*env=*/nullptr, stderr_stream,
                       /*stdout_to_stderr=*/false);
}
