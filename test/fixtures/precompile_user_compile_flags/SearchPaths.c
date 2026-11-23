#include "SearchPaths.h"

int search_paths_fixture_value(void) {
  return SEARCH_PATH_FROM_INCLUDE + SEARCH_PATH_FROM_IQUOTE +
         SEARCH_PATH_FROM_ISYSTEM + SEARCH_PATH_FROM_SEPARATED;
}
