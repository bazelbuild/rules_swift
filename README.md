# Swift Rules for [Bazel](https://bazel.build)

[![Build status](https://badge.buildkite.com/d562b11425e192a8f6ba9c43715bc8364985bccf54e4b9194a.svg?branch=master)](https://buildkite.com/bazel/rules-swift-swift)

This repository contains rules for [Bazel](https://bazel.build) that can be
used to build Swift libraries, tests, and executables for macOS and Linux.

To build applications for all of Apple's platforms (macOS, iOS, tvOS, and
watchOS), they can be combined with the
[Apple Rules](https://github.com/bazelbuild/rules_apple).

If you run into any problems with these rules, please
[file an issue!](https://github.com/bazelbuild/rules_swift/issues/new)

## Reference Documentation

[Click here](https://github.com/bazelbuild/rules_swift/tree/master/doc)
for the reference documentation for the rules and other definitions in this
repository.

## Quick Setup

### 1. Install Swift

Before getting started, make sure that you have a Swift toolchain installed.

**Apple users:** Install [Xcode](https://developer.apple.com/xcode/downloads/).
If this is your first time installing it, make sure to open it once after
installing so that the command line tools are correctly configured.

**Linux users:** Follow the instructions on the
[Swift download page](https://swift.org/download/) to download and install the
appropriate Swift toolchain for your platform. Take care to ensure that you have
all of Swift's dependencies installed (such as ICU, Clang, and so forth), and
also ensure that the Swift compiler is available on your system path.

### 2. Configure your workspace

Copy the `WORKSPACE` snippet from [the releases
page](https://github.com/bazelbuild/rules_swift/releases).

### 3. Additional configuration (Linux only)

The `swift_binary` and `swift_test` rules expect to use `clang` as the driver
for linking, and they query the Bazel C++ API and CROSSTOOL to determine which
arguments should be passed to the linker. By default, the C++ toolchain used by
Bazel is `gcc`, so Swift users on Linux need to override this by setting the
environment variable `CC=clang` when invoking Bazel.

This step is not necessary for macOS users because the Xcode toolchain always
uses `clang`.

## Building with Custom Toolchains

**macOS hosts:** You can build with a custom toolchain installed in
`/Library/Developer/Toolchains` instead of Xcode's default. To do so, pass the
following flag to Bazel:

```lang-none
--define=SWIFT_CUSTOM_TOOLCHAIN=toolchain.id
```

where `toolchain.id` is the value of the `CFBundleIdentifier` key in the
toolchain's Info.plist file.

To list the available toolchains and their bundle identifiers, you can run:

```command
bazel run @build_bazel_rules_swift//tools/dump_toolchains
```

**Linux hosts:** At this time, Bazel uses whichever `swift` executable is
encountered first on your `PATH`.

## Supporting debugging

To make cacheable builds work correctly with debugging see
[this doc](doc/debuggable_remote_swift.md).

## Swift Package Manager Support

To download, build, and reference external Swift packages as Bazel targets, check out
[rules_spm](https://github.com/cgrindel/rules_spm).  The rules in
[rules_spm](https://github.com/cgrindel/rules_spm) build external Swift packages with [Swift
Package Manager](https://swift.org/package-manager/), then make the outputs available to Bazel
rules.

## Future Work

- Support for building and linking to shared libraries (`.dylib`/`.so`) written
  in Swift.
- Migration to the Bazel platforms/toolchains APIs.
- Support for multiple toolchains, and support for non-Xcode toolchains on
  macOS.
- Automatically download a Linux toolchain from [swift.org](https://swift.org)
  if one is not already installed.

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
| 6.x (most recent rolling) | 0.27.0 | current |
| 5.x | 0.25.0 | current |
| 4.x | 0.19.0 | 0.24.0 |
| 3.x | 0.14.0 | 0.18.0 |

## Acknowledgments

We gratefully acknowledge the following external packages that rules_swift
depends on:

- [Apple Support for Bazel](https://github.com/bazelbuild/apple_support) (Google)
- [Bazel Skylib](https://github.com/bazelbuild/bazel-skylib) (Google)
- [JSON for Modern C++](https://github.com/nlohmann/json) (Niels Lohmann)
- [Protocol Buffers](https://github.com/protocolbuffers/protobuf) (Google)
- [Swift gRPC](https://github.com/grpc/grpc-swift) (Google)
- [Swift Protobuf](https://github.com/apple/swift-protobuf) (Apple)
- [zlib](https://www.zlib.net) (Jean-loup Gailly and Mark Adler)
