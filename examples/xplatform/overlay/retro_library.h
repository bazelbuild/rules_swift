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

#ifndef THIRD_PARTY_BAZEL_RULES_RULES_SWIFT_EXAMPLES_XPLATFORM_OVERLAY_RETRO_LIBRARY_H_
#define THIRD_PARTY_BAZEL_RULES_RULES_SWIFT_EXAMPLES_XPLATFORM_OVERLAY_RETRO_LIBRARY_H_

typedef struct _RetroRect {
  float x;
  float y;
  float width;
  float height;
} RetroRect;

float RetroRectArea(RetroRect r)
    __attribute__((swift_name("getter:RetroRect.area(self:)")));

void RetroRectPrint(RetroRect r)
    __attribute__((swift_name("RetroRect.print(self:)")));

#endif  // THIRD_PARTY_BAZEL_RULES_RULES_SWIFT_EXAMPLES_XPLATFORM_OVERLAY_RETRO_LIBRARY_H_
