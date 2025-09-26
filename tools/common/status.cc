// Copyright 2022 The Bazel Authors. All rights reserved.
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

#include "tools/common/status.h"

#include <cerrno>

#include "absl/strings/str_format.h"
#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

absl::Status MakeStatusFromErrno(absl::string_view message) {
  absl::StatusCode status_code;
  int preserved_errno = errno;

  switch (preserved_errno) {
    case ECANCELED:
      status_code = absl::StatusCode::kCancelled;
      break;
    case EINVAL:
      status_code = absl::StatusCode::kInvalidArgument;
      break;
    case ETIMEDOUT:
      status_code = absl::StatusCode::kDeadlineExceeded;
      break;
    case ENOENT:
      status_code = absl::StatusCode::kNotFound;
      break;
    case EEXIST:
      status_code = absl::StatusCode::kAlreadyExists;
      break;
    case EACCES:
      status_code = absl::StatusCode::kPermissionDenied;
      break;
    case ENOMEM:
      status_code = absl::StatusCode::kResourceExhausted;
      break;
    case ENOTSUP:
      status_code = absl::StatusCode::kFailedPrecondition;
      break;
    case ERANGE:
      status_code = absl::StatusCode::kOutOfRange;
      break;
    default:
      status_code = absl::StatusCode::kUnknown;
  }

  const int kErrBufferSize = 512;
  char err_buffer[kErrBufferSize] = {0};
  strerror_r(preserved_errno, err_buffer, kErrBufferSize);

  return absl::Status(status_code,
                      absl::StrFormat("%s (errno %d: %s)", message,
                                      preserved_errno, err_buffer));
}

}  // namespace bazel_rules_swift
