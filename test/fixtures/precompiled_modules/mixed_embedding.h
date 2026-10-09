#include "embedded_textual_header.h"

// Read the embedded header's source locations before the system header's.
// These warnings are intentional: their notes load the shared macro definition.
static inline int readEmbeddedTextualValue(void) {
  return embeddedTextualValue;
}

#include "system_textual_header.h"

static inline int readSystemTextualValue(void) {
  return systemTextualValue;
}
