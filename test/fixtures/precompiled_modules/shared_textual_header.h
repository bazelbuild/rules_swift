// Give each PCM a distinct macro so expanding both reads this textual header's
// source locations from both the workspace and system PCMs.
#ifdef BUILD_EMBEDDED_TEXTUAL_HEADER
#define EMBEDDED_TEXTUAL_VALUE 1
#else
#define SYSTEM_TEXTUAL_VALUE 2
#endif
