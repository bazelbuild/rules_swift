load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)

licenses(["notice"])

# A library that contains both C and Swift sources, including a public header.
swift_library(
    name = "simple",
    srcs = [
        "Simple.c",
        "Simple.swift",
    ],
    hdrs = [
        "Simple.h",
    ],
    module_name = "Simple",
)

swift_test(
    name = "swift_test",
    srcs = ["main.swift"],
    discover_tests = False,
    deps = [
        ":simple",
    ],
)

# Make sure a C++ target can also depend on the mixed library and use the C++
# bits.
cc_test(
    name = "cc_test",
    srcs = ["main.cc"],
    deps = [":simple"],
)

test_suite(
    name = "srcs_and_hdrs",
)
