#include "sysroot.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <numeric>
#include <vector>

int main() {
  const std::vector<long> values{parse_sysroot_number("20"),
                                 parse_sysroot_number("22")};
  std::atomic<long> total{std::accumulate(values.begin(), values.end(), 0L)};
  const auto now = std::chrono::steady_clock::now();
  if (total.load() != 42 || parse_sysroot_number("invalid") != -1 ||
      now.time_since_epoch().count() <= 0) {
    std::fputs("sysroot C/C++ runtime check failed\n", stderr);
    return 1;
  }
  return 0;
}
