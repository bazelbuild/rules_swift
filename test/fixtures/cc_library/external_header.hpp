#pragma once

#include <cerrno>
#include <streambuf>

// NOTE: Must come below streambuf
#include <nlohmann/json.hpp>

namespace Test {
using json = nlohmann::json;
}
