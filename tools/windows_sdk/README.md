# Windows SDKs for cross-compiling from Linux

`swift.windows_sdk` builds Swift, C and C++ for Windows (`aarch64` and
`x86_64`) on a Linux host, with the host toolchain's `swiftc`, `clang-cl`,
`lld-link` and `llvm-ar`. Like an Xcode for Apple's platforms, the two SDKs it
needs are the builder's to bring: make them once with these scripts and host
them where your builds can fetch them (a file server, an artifact store, a
`--distdir`, a `--downloader_config` rewrite).

```starlark
swift = use_extension("@rules_swift//swift:extensions.bzl", "swift")
swift.toolchain(name = "swift_toolchain", swift_version = "6.3.2")
swift.windows_sdk(
    url = "https://example.com/swift-windows-sdk-6.3.2.tar.gz",
    sha256 = "…",
    msvc_url = "https://example.com/msvc-sysroot.tar.gz",
    msvc_sha256 = "…",
)
use_repo(swift, "swift_toolchain")
register_toolchains("@swift_toolchain//:all")
```

Then build with `--platforms` naming a platform with `@platforms//os:windows`
and `@platforms//cpu:aarch64` (or `x86_64`). A `swift_binary`'s `.exe` needs
the Swift runtime's DLLs beside it:
`@swift_toolchain_windows_sdk_<host platform>//:runtime_aarch64`.

## The Windows Swift SDK

`make_swift_sdk.sh <installer> <out.tar.gz>` extracts swift.org's Windows
toolchain installer (`swift-<version>-RELEASE-windows10-arm64.exe`, the same
release as the host toolchain) on Linux, with 7-Zip and msitools: its
`Windows.platform` (the SDK, XCTest and Testing) and the runtime's DLLs for
`aarch64` and `x86_64`, with a `VERSION` file. It is Apache-licensed, as
Swift is.

## The MSVC sysroot

The Windows SDK's and MSVC's headers and import libraries. Microsoft's license
lets them be used, not redistributed, so each builder makes their own:

1. On a Windows machine with the Visual Studio Build Tools:
   `powershell -File make_msvc_sysroot.ps1` writes `C:\winsysroot.tar.gz`, in
   clang's `/winsysroot` layout.
2. On Linux with Swift: `make_msvc_sysroot.sh <winsysroot.tar.gz>
   <swift-windows-sdk.tar.gz> <out.tar.gz>` adds the symbolic links a
   case-sensitive file system needs (Windows' headers include each other, and
   Swift's module maps name them, in casings other than the files' own) and a
   `VERSIONS` file naming MSVC's and the SDK's versions.
