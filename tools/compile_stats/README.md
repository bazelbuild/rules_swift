# compile_stats/build.sh helper

This script conveniently wraps up the various Bazel arguments needed to collect
timing statistics from the Swift compiler.

## Usage

```
build.sh [arguments]
```

where `[arguments]` is a list of arguments that should be passed directly to
Bazel (such as targets to build, or additional flags).

The output of this script will be a listing of the JSON timings files that were
generated for _every_ Swift target in the build.
