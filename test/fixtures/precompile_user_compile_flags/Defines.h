#ifndef DEFINES_FIXTURE_H
#define DEFINES_FIXTURE_H

// If the defines are missing, creating the PCM will fail
#if !defined(FIXTURE_FROM_COPTS)
#error "FIXTURE_FROM_COPTS was not defined when compiling the module"
#endif

#if !defined(FIXTURE_FROM_LOCAL_DEFINES)
#error "FIXTURE_FROM_LOCAL_DEFINES was not defined when compiling the module"
#endif

int defines_fixture_value(void);

#endif
