# compile_stats/build.sh helper

This script conveniently wraps up the various Bazel arguments needed to collect
timing statistics from the Swift compiler.

## Usage

```
build.sh [arguments]
```

where `[arguments]` is a list of arguments that should be passed directly to
Bazel (such as targets to build, or additional flags).

The output of this script will be a Markdown-formatted consolidated report that
shows the driver and frontend timings for the jobs that were invoked across
_every_ Swift target in the build, with the slowest driver invocations at the
top (and the slowest frontend invocations at the top within those groups).
