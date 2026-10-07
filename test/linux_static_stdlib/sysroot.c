#include "sysroot.h"

#include <errno.h>
#include <stdlib.h>

long parse_sysroot_number(const char* text) {
  char* end;
  errno = 0;
  long value = strtol(text, &end, 10);
  return errno == 0 && end != text && *end == '\0' ? value : -1;
}
