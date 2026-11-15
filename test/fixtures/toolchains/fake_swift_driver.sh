#!/usr/bin/env bash

# A stand-in for a custom Swift driver, used to test the `swift_executable`
# attribute and the `//swift:default_swift_executable` flag.
echo "fake_swift_driver.sh invoked with: $*" >&2
exit 1
