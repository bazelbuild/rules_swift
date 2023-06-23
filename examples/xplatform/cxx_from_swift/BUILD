load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_interop_hint.bzl",
    "swift_interop_hint",
)

licenses(["notice"])

cc_library(
    name = "counter",
    srcs = ["counter.cc"],
    hdrs = ["counter.h"],
    aspect_hints = [":counter_swift_hint"],
)

swift_interop_hint(
    name = "counter_swift_hint",
    module_name = "CounterModule",
)

swift_binary(
    name = "cxx_from_swift",
    srcs = ["main.swift"],
    cxx_interop = "default",
    module_name = "main",
    deps = [":counter"],
)
