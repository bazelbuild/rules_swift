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

## Compatibility

Please refer to the
[release notes](https://github.com/bazelbuild/rules_swift/releases) for a given
release to see which version of Bazel it is compatible with.

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

Add the following to your `WORKSPACE` file to add the external repositories,
replacing the `urls` and `sha256` attributes with the values from the release
you wish to depend on:

```python
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "build_bazel_rules_swift",
    urls = [
        "https://github.com/bazelbuild/rules_swift/releases/download/0.8.0/rules_swift.0.8.0.tar.gz",
    ],
    sha256 = "31aad005a9c4e56b256125844ad05eb27c88303502d74138186f9083479f93a6",
)

load(
    "@build_bazel_rules_swift//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()

load(
    "@build_bazel_apple_support//lib:repositories.bzl",
    "apple_support_dependencies",
)

apple_support_dependencies()
```

The `swift_rules_dependencies` macro creates a toolchain appropriate for your
platform (either by locating an installation of Xcode on macOS, or looking for
`swiftc` on the system path on Linux).

### 3. Additional configuration (Linux only)

The `swift_binary` and `swift_test` rules expect to use `clang` as the driver
for linking, and they query the Bazel C++ API and CROSSTOOL to determine which
arguments should be passed to the linker. By default, the C++ toolchain used by
Bazel is `gcc`, so Swift users on Linux need to override this by setting the
environment variable `CC=clang` when invoking Bazel.

This step is not necessary for macOS users because the Xcode toolchain always
uses `clang`.

## Future Work

* Support for building and linking to shared libraries (`.dylib`/`.so`) written
  in Swift.
* Interoperability with Swift Package Manager.
* Migration to the Bazel platforms/toolchains APIs.
* Support for multiple toolchains, and support for non-Xcode toolchains on
  macOS.
* Automatically download a Linux toolchain from [swift.org](https://swift.org)
  if one is not already installed.

## Acknowledgments

We gratefully acknowledge the following external packages that rules_swift
depends on:

* [Apple Support for Bazel](https://github.com/bazelbuild/apple_support) (Google)
* [Bazel Skylib](https://github.com/bazelbuild/bazel-skylib) (Google)
* [JSON for Modern C++](https://github.com/nlohmann/json) (Niels Lohmann)
* [Protocol Buffers](https://github.com/protocolbuffers/protobuf) (Google)
* [Swift gRPC](https://github.com/grpc/grpc-swift) (Google)
* [Swift Protobuf](https://github.com/apple/swift-protobuf) (Apple)
* [zlib](https://www.zlib.net) (Jean-loup Gailly and Mark Adler)
