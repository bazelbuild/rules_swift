load(
    "//swift:swift_binary.bzl",
    "swift_binary",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)

package(
    default_visibility = [
        "//test:__subpackages__",
    ],
)

licenses(["notice"])

swift_library(
    name = "dep",
    srcs = ["dep.swift"],
    tags = ["manual"],
)

swift_library(
    name = "lib_parallel",
    srcs = ["main.swift"],
    features = [
        "swift.compile_in_parallel",
        "swift.layering_check_swift",
    ],
    tags = ["manual"],
    deps = [":dep"],
)

swift_library(
    name = "lib_codegen_layering",
    srcs = ["main.swift"],
    features = [
        "swift._layering_check_on_codegen",
        "swift.compile_in_parallel",
        "swift.layering_check_swift",
    ],
    tags = ["manual"],
    deps = [":dep"],
)

swift_binary(
    name = "bin_parallel",
    srcs = ["main.swift"],
    features = [
        "swift.compile_in_parallel",
        "swift.layering_check_swift",
    ],
    tags = ["manual"],
    deps = [":dep"],
)

swift_library(
    name = "lib_single",
    srcs = ["main.swift"],
    features = [
        "-swift.compile_in_parallel",
        "swift.layering_check_swift",
    ],
    tags = ["manual"],
    deps = [":dep"],
)
