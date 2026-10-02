load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)

licenses(["notice"])

# A simple binary that ensures that symbols from C sources in the same target
# are linked correctly into the binary.
swift_test(
    name = "simple",
    srcs = [
        "Private.h",
        "Simple.c",
        "Simple.swift",
    ],
    c_copts = ["-DMIXED_LANGUAGE_FACTOR=1"],
    discover_tests = False,
)

swift_library(
    name = "simple_library",
    srcs = [
        "Library.swift",
        "Private.h",
        "Simple.c",
    ],
    c_copts = ["-DMIXED_LANGUAGE_FACTOR=1"],
    module_name = "MixedCSwiftLibrary",
)

swift_test(
    name = "library_client",
    srcs = ["LibraryClient.swift"],
    discover_tests = False,
    deps = [":simple_library"],
)

swift_test(
    name = "objc",
    srcs = [
        "ObjcClient.swift",
        "Simple.m",
    ],
    discover_tests = False,
    target_compatible_with = ["@platforms//os:macos"],
)
