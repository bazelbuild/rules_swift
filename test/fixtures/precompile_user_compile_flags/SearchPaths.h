#ifndef SEARCH_PATHS_FIXTURE_H
#define SEARCH_PATHS_FIXTURE_H

// These headers are found only through the target's private -I, -iquote, and
// -isystem copts, in joined and separated forms. If those copts are missing,
// creating the PCM will fail.
#include <search_path_from_isystem.h>
#include <search_path_from_separated.h>

#include "search_path_from_include.h"
#include "search_path_from_iquote.h"

// A separated flag must not consume the flag that follows its argument.
#if !defined(SEARCH_PATHS_AFTER_SEPARATED)
#error "SEARCH_PATHS_AFTER_SEPARATED was not defined when compiling the module"
#endif

#if !defined(SEARCH_PATHS_AFTER_MAKE_VARIABLE)
#error \
    "SEARCH_PATHS_AFTER_MAKE_VARIABLE was not defined when compiling the module"
#endif

int search_paths_fixture_value(void);

#endif
