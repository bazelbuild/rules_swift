load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)

licenses(["notice"])

# We need to enable C++ interop on this binary's dependencies, which `cc_binary`
# can't do. Instead, we use a `swift_binary` to set the flag, and move the main
# C++ code into an alwayslink `cc_library` for the same effect.
swift_binary(
    name = "swift_from_cxx",
    cxx_interop = "default",
    deps = [":swift_from_cxx_cclib"],
)

cc_library(
    name = "swift_from_cxx_cclib",
    srcs = ["main.cc"],
    deps = [":counter"],
    alwayslink = True,
)

swift_library(
    name = "counter",
    srcs = ["Counter.swift"],
    generates_header = True,
    module_name = "CounterModule",
)
