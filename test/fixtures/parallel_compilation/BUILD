load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(
    ":rules.bzl",
    "const_gather_dep",
    "generate_swift_sources",
)

package(
    default_visibility = ["//test:__subpackages__"],
    features = ["swift.compile_in_parallel"],
)

licenses(["notice"])

###############################################################################

swift_library(
    name = "no_opt_no_wmo",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "no_opt_with_wmo",
    srcs = ["Empty.swift"],
    copts = ["-wmo"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_opt_no_wmo",
    srcs = ["Empty.swift"],
    copts = ["-O"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_opt_with_wmo_no_cmo",
    srcs = ["Empty.swift"],
    copts = [
        "-O",
        "-wmo",
    ],
    features = ["-swift.opt_uses_cmo"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_opt_with_wmo_with_cmo",
    srcs = ["Empty.swift"],
    copts = [
        "-O",
        "-wmo",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "with_opt_with_wmo_with_library_evolution",
    srcs = ["Empty.swift"],
    copts = [
        "-O",
        "-wmo",
    ],
    library_evolution = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "onone_with_wmo",
    srcs = ["Empty.swift"],
    copts = [
        "-Onone",
        "-wmo",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "header_and_interface",
    srcs = ["Empty.swift"],
    generates_header = True,
    library_evolution = True,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "layering_check_on_codegen",
    srcs = ["Empty.swift"],
    features = [
        "swift.layering_check_swift",
        "swift._layering_check_on_codegen",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "legacy_batch_mode",
    srcs = ["Empty.swift"],
    features = [
        "-swift.compile_in_parallel",
        "swift.enable_batch_mode",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "index_while_building",
    srcs = ["Empty.swift"],
    features = [
        "swift.index_while_building",
        "swift.modular_indexing",
        "swift.use_c_modules",
    ],
    tags = FIXTURE_TAGS,
)

generate_swift_sources(
    name = "nine_sources",
    count = 9,
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "multi_batch",
    srcs = [":nine_sources"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "multi_batch_layering_check_on_codegen",
    srcs = [":nine_sources"],
    features = [
        "swift.layering_check_swift",
        "swift._layering_check_on_codegen",
    ],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "multi_batch_with_indexing",
    srcs = [":nine_sources"],
    features = ["swift.index_while_building"],
    tags = FIXTURE_TAGS,
)

const_gather_dep(
    name = "const_protocol_dep",
    const_gather_protocols = ["MyConstProtocol"],
    tags = FIXTURE_TAGS,
)

swift_library(
    name = "const_values",
    srcs = ["Empty.swift"],
    tags = FIXTURE_TAGS,
    deps = [":const_protocol_dep"],
)

swift_library(
    name = "const_values_driver_flag",
    srcs = ["Empty.swift"],
    features = ["swift._supports_const_gather_protocols_list"],
    tags = FIXTURE_TAGS,
    deps = [":const_protocol_dep"],
)

swift_library(
    name = "const_values_legacy",
    srcs = ["Empty.swift"],
    features = ["-swift._supports_const_gather_protocols_list"],
    tags = FIXTURE_TAGS,
    deps = [":const_protocol_dep"],
)

swift_library(
    name = "const_values_wmo",
    srcs = ["Empty.swift"],
    copts = ["-wmo"],
    tags = FIXTURE_TAGS,
    deps = [":const_protocol_dep"],
)

swift_library(
    name = "const_values_wmo_driver_flag",
    srcs = ["Empty.swift"],
    copts = ["-wmo"],
    features = ["swift._supports_const_gather_protocols_list"],
    tags = FIXTURE_TAGS,
    deps = [":const_protocol_dep"],
)
