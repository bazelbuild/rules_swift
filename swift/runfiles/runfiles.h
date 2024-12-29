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

// This header file defines a C API wrapper for the C++ Runfiles lookup library.
// The original C++ library was not directly compatible with Swift C++ interop
// (std::vector, std::unique_ptr, no copy ctors), hence the need for a wrapper.
// 
// Additionally, using a C++ API would have required users to manually set
// `-cxx-interoperability-mode=default`, hence the decision to use a C API which
// makes that transparent.

#ifndef _RULES_SWIFT_RUNFILES_H_
#define _RULES_SWIFT_RUNFILES_H_ 1

#include <stddef.h>

void *Runfiles_CreateForTest(const char *source_repository, char **error);
void *Runfiles_Create(const char *argv0, const char *source_repository,
                      char **error);
void *Runfiles_Create2(const char *argv0, const char *runfiles_manifest_file,
                       const char *runfiles_dir, const char *source_repository,
                       char **error);

char *Runfiles_Rlocation(void *handle, const char *path);
char *Runfiles_RlocationFrom(void *handle, const char *path,
                             const char *source_repository);

char **Runfiles_EnvVars(void *handle, size_t *size);

void *Runfiles_WithSourceRepository(void *handle,
                                    const char *source_repository);

void Runfiles_Destroy(void *handle);

// } // namespace swiftrunfiles

#endif
