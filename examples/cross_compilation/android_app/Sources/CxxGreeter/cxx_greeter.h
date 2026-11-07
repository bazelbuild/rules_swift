#pragma once

#include <cstddef>
#include <string>

inline std::string cxxGreeting(const std::string &subject) {
  return "Hello from C++, " + subject + "!";
}
