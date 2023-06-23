load(
    "//swift:swift_library.bzl",
    "swift_library",
)

licenses(["notice"])

swift_library(
    name = "counter",
    srcs = ["Counter.swift"],
    cxx_interop = "default",
    generates_header = True,
    module_name = "CounterModule",
)

cc_binary(
    name = "swift_from_cxx",
    srcs = ["main.cc"],
    deps = [":counter"],
)
