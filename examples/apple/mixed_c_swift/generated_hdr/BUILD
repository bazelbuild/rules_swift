load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)

licenses(["notice"])

# A library that contains both C and Swift sources, including a public header,
# and which also generates an Obj-C header.
swift_library(
    name = "Multiplier",
    srcs = [
        "Multiplier.m",
        "Squarer.swift",
    ],
    hdrs = [
        "Multiplier.h",
    ],
    generates_header = True,
    module_name = "Multiplier",
)

swift_test(
    name = "generated_hdr",
    srcs = ["main.swift"],
    discover_tests = False,
    deps = [
        ":Multiplier",
    ],
)
