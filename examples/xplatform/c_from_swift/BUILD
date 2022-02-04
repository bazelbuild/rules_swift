load("//swift:swift.bzl", "swift_binary", "swift_library")

licenses(["notice"])

# 1. This library has some C++ code that you want to interact with from Swift...
cc_library(
    name = "counter",
    srcs = ["counter.cc"],
    hdrs = ["counter.h"],
)

# 2. ...but Swift can't import C++ yet, so we implement a wrapper API in C.
cc_library(
    name = "c_counter",
    srcs = ["c_counter.cc"],
    hdrs = ["c_counter.h"],
    tags = ["swift_module=CCounter"],
    deps = [":counter"],
)

# 3. The Swift library then depends on the `cc_library`. This causes a
# Swift-compatible module map to be created for the `cc_library` so that the
# Swift code can import it.
swift_library(
    name = "swift_counter",
    srcs = ["Counter.swift"],
    module_name = "Counter",
    deps = [":c_counter"],
)

# 4. Finally, this binary is a straightforward target with no surprises. It just
# imports the Swift `Counter` module above.
swift_binary(
    name = "c_from_swift",
    srcs = ["main.swift"],
    module_name = "main",
    deps = [":swift_counter"],
)
