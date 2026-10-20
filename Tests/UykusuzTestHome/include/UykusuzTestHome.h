#ifndef UYKUSUZ_TEST_HOME_H
#define UYKUSUZ_TEST_HOME_H

/// Name of the environment variable the loader sets ("UYKUSUZ_HOME").
const char *uykusuz_test_home_key(void);

/// The throwaway directory UYKUSUZ_HOME was pointed at when the test bundle
/// loaded, or NULL if the loader has not run.
const char *uykusuz_test_home_root(void);

#endif
