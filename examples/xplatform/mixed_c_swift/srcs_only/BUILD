load(
    "//swift:swift_test.bzl",
    "swift_test",
)

licenses(["notice"])

# A simple binary that ensures that symbols from C sources in the same target
# are linked correctly into the binary.
swift_test(
    name = "srcs_only",
    srcs = [
        "Simple.c",
        "main.swift",
    ],
    discover_tests = False,
)
