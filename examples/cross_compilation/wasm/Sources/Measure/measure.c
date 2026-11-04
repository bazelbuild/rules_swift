#include "examples/cross_compilation/wasm/Sources/Measure/measure.h"

size_t measure_length(const char *string) {
  size_t length = 0;
  while (string[length] != '\0') {
    length++;
  }
  return length;
}
