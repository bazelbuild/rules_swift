#ifndef NO_COPTS_TOKENIZATION_FIXTURE_H
#define NO_COPTS_TOKENIZATION_FIXTURE_H

#if !defined(FIXTURE_NO_COPTS_TOKENIZATION)
#error "FIXTURE_NO_COPTS_TOKENIZATION was not defined when compiling the module"
#endif

#define NO_COPTS_TOKENIZATION_STRINGIFY_INNER(value) #value
#define NO_COPTS_TOKENIZATION_STRINGIFY(value) \
  NO_COPTS_TOKENIZATION_STRINGIFY_INNER(value)
typedef char no_copts_tokenization_define_has_expected_value
    [sizeof(NO_COPTS_TOKENIZATION_STRINGIFY(FIXTURE_NO_COPTS_TOKENIZATION)) ==
             sizeof("rules swift fixture")
         ? 1
         : -1];

int no_copts_tokenization_fixture_value(void);

#endif
