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
        "Simple.c",
        "Simple.swift",
    ],
    discover_tests = False,
)
