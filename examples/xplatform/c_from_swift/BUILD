load(
    "@build_bazel_rules_swift//swift:swift.bzl",
    "swift_binary",
    "swift_c_module",
    "swift_library",
)

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
    deps = [":counter"],
)

# 3. Since `cc_library` targets don't write out module maps that are compatible
# with Swift imports, we provide our own and wrap the original library in a new
# target.
swift_c_module(
    name = "counter_module",
    module_map = "module.modulemap",
    deps = [":c_counter"],
)

# 4. The Swift library then depends on the module and imports it in its Swift
# code.
swift_library(
    name = "swift_counter",
    srcs = ["Counter.swift"],
    module_name = "Counter",
    deps = [":counter_module"],
)

# 5. Finally, this binary is a straightforward target with no surprises. It just
# imports the Swift `Counter` module above.
swift_binary(
    name = "c_from_swift",
    srcs = ["main.swift"],
    module_name = "main",
    deps = [":swift_counter"],
)
