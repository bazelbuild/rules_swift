#ifndef DEFINES_FIXTURE_H
#define DEFINES_FIXTURE_H

// If the defines are missing, creating the PCM will fail
#if !defined(FIXTURE_FROM_COPTS)
#error "FIXTURE_FROM_COPTS was not defined when compiling the module"
#endif

#if !defined(FIXTURE_FROM_COPTS_WITH_SPACES)
#error \
    "FIXTURE_FROM_COPTS_WITH_SPACES was not defined when compiling the module"
#endif

#define FIXTURE_STRINGIFY_INNER(value) #value
#define FIXTURE_STRINGIFY(value) FIXTURE_STRINGIFY_INNER(value)
typedef char fixture_define_with_spaces_has_expected_value
    [sizeof(FIXTURE_STRINGIFY(FIXTURE_FROM_COPTS_WITH_SPACES)) ==
             sizeof("rules swift fixture")
         ? 1
         : -1];

#if !defined(FIXTURE_FROM_QUOTED_COPTS)
#error "FIXTURE_FROM_QUOTED_COPTS was not defined when compiling the module"
#endif

typedef char fixture_quoted_define_has_expected_value
    [sizeof(FIXTURE_STRINGIFY(FIXTURE_FROM_QUOTED_COPTS)) ==
             sizeof("quoted rules swift fixture")
         ? 1
         : -1];

#if !defined(FIXTURE_FROM_LOCAL_DEFINES)
#error "FIXTURE_FROM_LOCAL_DEFINES was not defined when compiling the module"
#endif

int defines_fixture_value(void);

#endif
