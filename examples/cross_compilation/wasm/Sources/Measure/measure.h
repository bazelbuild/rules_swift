#ifndef MEASURE_H_
#define MEASURE_H_

#include <stddef.h>

/// Returns the number of bytes before the NUL terminator of `string`.
size_t measure_length(const char *string);

#endif  // MEASURE_H_
