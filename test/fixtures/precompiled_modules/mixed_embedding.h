#include "embedded_textual_header.h"

// Expand the embedded macro before the system macro so Clang reads the shared
// header's embedded source locations before its non-embedded source locations.
_Static_assert(EMBEDDED_TEXTUAL_VALUE == 1, "embedded textual macro");

#include "system_textual_header.h"

_Static_assert(SYSTEM_TEXTUAL_VALUE == 2, "system textual macro");
