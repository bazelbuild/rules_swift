# Swift Rules for [Bazel](https://bazel.build)

[![Build Status](https://travis-ci.org/bazelbuild/rules_swift.svg?branch=master)](https://travis-ci.org/bazelbuild/rules_swift)

> ⚠️ The rules in this repository are in the beta stage of development. There are
> many features that still need to be implemented and there may be bugs. If you
> run into any problems, please
> [file an issue!](https://github.com/bazelbuild/rules_swift/issues/new)

This repository contains rules for [Bazel](https://bazel.build) that can be
used to build Swift libraries and executables for Apple platforms (iOS, macOS,
tvOS, and watchOS) and Linux.

NOTE: The build rules in this repository are intended to replace the
`swift_library` rule that is currently housed in
[bazelbuild/rules_apple](https://github.com/bazelbuild/rules_apple).

## Reference Documentation

[Click here](https://github.com/bazelbuild/rules_swift/tree/master/doc/index.md)
for the reference documentation for the rules and other definitions in this
repository.

## Compatibility

These rules have been verified to work with **Bazel 0.16.0.**

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
replacing the version number in the `tag` attribute with the version of the
rules you wish to depend on:

```python
git_repository(
    name = "build_bazel_rules_swift",
    remote = "https://github.com/bazelbuild/rules_swift.git",
    tag = "0.3.0",
)

load(
    "@build_bazel_rules_swift//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()
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
* Improved C interoperability.
* Migration to the Bazel platforms/toolchains APIs.
* Support for multiple toolchains, and support for non-Xcode toolchains on
  macOS.
* Automatically download a Linux toolchain from [swift.org](https://swift.org)
  if one is not already installed.
