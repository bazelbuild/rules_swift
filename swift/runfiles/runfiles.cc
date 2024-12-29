// Copyright 2024 The Bazel Authors. All rights reserved.
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

#include "rules_cc/cc/runfiles/runfiles.h"

static char *CopyStringToC(const std::string &str) {
  char *cstr = static_cast<char *>(std::malloc(str.size() + 1));
  std::memcpy(cstr, str.data(), str.size());
  cstr[str.size()] = '\0';
  return cstr;
}

extern "C" {

void *Runfiles_CreateForTest(const char *source_repository, char **error) {
  std::string err;
  auto *runfiles = rules_cc::cc::runfiles::Runfiles::CreateForTest(
      std::string(source_repository), &err);
  if (!runfiles && error) {
    *error = CopyStringToC(err);
    return nullptr;
  }
  return runfiles;
}

void *Runfiles_Create(const char *argv0, const char *source_repository,
                      char **error) {
  std::string err;
  auto *runfiles = rules_cc::cc::runfiles::Runfiles::Create(
      std::string(argv0), std::string(source_repository), &err);
  if (!runfiles && error) {
    *error = CopyStringToC(err);
    return nullptr;
  }
  return runfiles;
}

void *Runfiles_Create2(const char *argv0, const char *runfiles_manifest_file,
                       const char *runfiles_dir, const char *source_repository,
                       char **error) {
  std::string err;
  auto *runfiles = rules_cc::cc::runfiles::Runfiles::Create(
      std::string(argv0), std::string(runfiles_manifest_file),
      std::string(runfiles_dir), std::string(source_repository), &err);
  if (!runfiles && error) {
    *error = CopyStringToC(err);
    return nullptr;
  }
  return runfiles;
}

char *Runfiles_Rlocation(void *handle, const char *path) {
  auto *runfiles = static_cast<rules_cc::cc::runfiles::Runfiles *>(handle);
  std::string result = runfiles->Rlocation(std::string(path));
  return CopyStringToC(result);
}

char *Runfiles_RlocationFrom(void *handle, const char *path,
                             const char *source_repository) {
  auto *runfiles = static_cast<rules_cc::cc::runfiles::Runfiles *>(handle);
  std::string result =
      runfiles->Rlocation(std::string(path), std::string(source_repository));
  return CopyStringToC(result);
}

char **Runfiles_EnvVars(void *handle, size_t *size) {
  auto *runfiles = static_cast<rules_cc::cc::runfiles::Runfiles *>(handle);
  auto &envVars = runfiles->EnvVars();
  char **cArray =
      static_cast<char **>(std::malloc(envVars.size() * 2 * sizeof(char *)));

  size_t index = 0;
  for (const auto &pair : envVars) {
    cArray[index++] = CopyStringToC(pair.first);   // Copy key
    cArray[index++] = CopyStringToC(pair.second);  // Copy value
  }

  *size = envVars.size() * 2;
  return cArray;
}

void *Runfiles_WithSourceRepository(void *handle,
                                    const char *source_repository) {
  auto *runfiles = static_cast<rules_cc::cc::runfiles::Runfiles *>(handle);
  auto runfiles_new = runfiles->WithSourceRepository(source_repository);
  return runfiles_new.release();
}

void Runfiles_Destroy(void *handle) {
  auto *runfiles = static_cast<rules_cc::cc::runfiles::Runfiles *>(handle);
  delete runfiles;
}

}  // extern "C"
