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

#ifndef BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_COLOR_H_
#define BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_COLOR_H_

#include <ostream>

#include "absl/strings/string_view.h"

namespace bazel_rules_swift {

// A color that can be passed to the constructor of `ColorStream` when wrapping
// an `ostream`.
class Color {
 public:
  static const Color kBoldRed;
  static const Color kBoldGreen;
  static const Color kBoldMagenta;
  static const Color kBoldWhite;
  static const Color kReset;

  friend std::ostream &operator<<(std::ostream &stream, Color color) {
    return stream << "\x1b[" << color.code_ << "m";
  }

 private:
  constexpr explicit Color(absl::string_view code) : code_(code) {}

  // The ANSI code for the color.
  absl::string_view code_;
};

inline constexpr const Color Color::kBoldRed = Color("1;31");
inline constexpr const Color Color::kBoldGreen = Color("1;32");
inline constexpr const Color Color::kBoldMagenta = Color("1;35");
inline constexpr const Color Color::kBoldWhite = Color("1;37");
inline constexpr const Color Color::kReset = Color("0");

// An RAII-style wrapper for an `std::ostream` that prints the ANSI code for a
// color when initialized and prints the reset code on destruction.
//
// Modeled loosely after the `llvm::WithColor` support class.
class WithColor {
 public:
  // Wraps the given `ostream` so that its output is in `color` for the duration
  // of the wrapper's lifetime.
  WithColor(std::ostream &stream, Color color) : stream_(stream) {
    stream << color;
  }

  ~WithColor() { stream_ << Color::kReset; }

  template <typename T>
  WithColor &operator<<(const T &value) {
    stream_ << value;
    return *this;
  }

  WithColor &operator<<(std::ostream &(*modifier)(std::ostream &)) {
    modifier(stream_);
    return *this;
  }

 private:
  // The wrapped `ostream`.
  std::ostream &stream_;
};

}  // namespace bazel_rules_swift

#endif  // BUILD_BAZEL_RULES_SWIFT_TOOLS_COMMON_COLOR_H_
