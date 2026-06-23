# Swift Rules for [Bazel](https://bazel.build)

[![Build status](https://badge.buildkite.com/d562b11425e192a8f6ba9c43715bc8364985bccf54e4b9194a.svg?branch=main)](https://buildkite.com/bazel/rules-swift-swift)

This repository contains rules for [Bazel](https://bazel.build) that can be
used to build Swift libraries, tests, and executables for macOS and Linux.

To build applications for all of Apple's platforms (macOS, iOS, tvOS,
visionOS, and watchOS), they can be combined with the
[Apple Rules](https://github.com/bazelbuild/rules_apple).

If you run into any problems with these rules, please
[file an issue!](https://github.com/bazelbuild/rules_swift/issues/new)

## Basic Examples

Create a simple CLI that can run on macOS or Linux:

```bzl
load("@rules_swift//swift:swift_binary.bzl", "swift_binary")

swift_binary(
    name = "cli",
    srcs = ["CLI.swift"],
)
```

Create a single library target that can be used by other targets in your
build:

```bzl
load("@rules_swift//swift:swift_library.bzl", "swift_library")

swift_library(
    name = "MyLibrary",
    srcs = ["MyLibrary.swift"],
    tags = ["manual"],
)
```

## Reference Documentation

[Click here](https://github.com/bazelbuild/rules_swift/tree/main/doc)
for the reference documentation for the rules and other definitions in this
repository.

## Quick Setup

### 1. Configure your workspace

Copy the `MODULE.bazel` snippet from
[the releases page](https://github.com/bazelbuild/rules_swift/releases), then
select the platform that matches your build host. `rules_swift` downloads the
selected Swift release and registers it as a hermetic Bazel toolchain; it does
not discover or use a Swift installation from the host.

See [Hermetic Swift toolchain](doc/standalone_toolchain.md) for the complete
setup and the supported platform names.

### 2. Install platform dependencies

**Apple users:** Install [Xcode](https://developer.apple.com/xcode/downloads/).
`rules_swift` uses the Xcode SDKs and Apple linker, but Swift compiler actions
use the hermetic toolchain declared in `MODULE.bazel`. If this is your first
time installing Xcode, open it once so that the command line tools are
configured.

**Linux users:** Install the system dependencies required by the selected
swift.org toolchain, including Clang and ICU.

### 3. Configure Clang (Linux only)

The `swift_binary` and `swift_test` rules expect to use `clang` as the driver
for linking, and they query the Bazel C++ API and CROSSTOOL to determine which
arguments should be passed to the linker. By default, the C++ toolchain used by
Bazel is `gcc`, so Swift users on Linux need to override this by setting the
environment variable `CC=clang` when invoking Bazel. The downloaded Swift
toolchain does not replace Bazel's C++ toolchain.

This step is not necessary for macOS users because the Xcode toolchain always
uses `clang`.

## Supporting debugging

To make cacheable builds work correctly with debugging see
[this doc](doc/debuggable_remote_swift.md).

## Swift Package Manager Support

To download, build, and reference external Swift packages as Bazel
targets, check out
[rules_swift_package_manager](https://github.com/cgrindel/rules_swift_package_manager).

## Supported bazel versions

rules_apple and rules_swift are often affected by changes in bazel
itself. This means you generally need to update these rules as you
update bazel.

You can also see the supported bazel versions in the notes for each
release on the [releases
page](https://github.com/bazelbuild/rules_swift/releases).

Besides these constraint this repo follows [semver](https://semver.org/)
as best as we can since the 1.0.0 release.

| Bazel release | Minimum supported rules version | Final supported rules version|
|:-------------------:|:-------------------:|:-------------------------:|
| 10.x (most recent rolling) | 3.5.0 | current |
| 9.x | 3.5.0 | current |
| 8.x | 1.14.0 | current |
| 7.x | 1.8.0 | 3.6.1 |
| 6.x | 0.27.0 | 2.8.2 |
| 5.x | 0.25.0 | 1.14.0 |
| 4.x | 0.19.0 | 0.24.0 |
| 3.x | 0.14.0 | 0.18.0 |
