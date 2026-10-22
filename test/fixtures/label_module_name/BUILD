load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
load(
    "//swift:swift_interop_hint.bzl",
    "swift_interop_hint",
)
load(
    "//swift:swift_library.bzl",
    "swift_library",
)
load(
    "//swift:swift_test.bzl",
    "swift_test",
)
load(
    "//test/fixtures:common.bzl",
    "FIXTURE_TAGS",
    "reexport_swift_info",
    "reexport_swift_interop_info",
)

package(
    default_visibility = [
        "//test:__subpackages__",
    ],
)

licenses(["notice"])

swift_library(
    name = "child",
    srcs = ["child.swift"],
    features = ["swift.label_as_module_name"],
    tags = ["manual"],
)

swift_library(
    name = "label_module_name",
    srcs = ["main.swift"],
    features = ["swift.label_as_module_name"],
    tags = ["manual"],
    deps = [":child"],
)

swift_library(
    name = "swift_custom_module_name",
    srcs = ["child.swift"],
    module_name = "CustomSwiftModule",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "objc_default",
    hdrs = ["header.h"],
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "objc_label_module_name",
    hdrs = ["header.h"],
    features = ["swift.label_as_module_name"],
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "objc_explicit_module_name",
    hdrs = ["header.h"],
    module_name = "ExplicitObjcModule",
    tags = FIXTURE_TAGS,
)

swift_interop_hint(
    name = "hinted_objc_module_hint",
    module_name = "HintedObjcModule",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "objc_hint_overrides_attr",
    hdrs = ["header.h"],
    aspect_hints = [":hinted_objc_module_hint"],
    module_name = "ExplicitObjcModule",
    tags = FIXTURE_TAGS,
)

objc_library(
    name = "objc_no_hdrs",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "cc_no_hint",
    hdrs = ["header.h"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "cc_auto_module_label",
    hdrs = ["header.h"],
    aspect_hints = ["//swift:auto_module"],
    features = ["swift.label_as_module_name"],
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "cc_no_hdrs_auto_module",
    aspect_hints = ["//swift:auto_module"],
    tags = FIXTURE_TAGS,
)

reexport_swift_info(
    name = "swift_multiple_modules",
    tags = FIXTURE_TAGS,
    deps = [
        ":child",
        ":swift_custom_module_name",
    ],
)

reexport_swift_interop_info(
    name = "interop_with_hdrs_and_direct_swift_infos",
    hdrs = ["header.h"],
    tags = FIXTURE_TAGS,
    deps = [
        ":child",
        ":swift_custom_module_name",
    ],
)

reexport_swift_interop_info(
    name = "interop_without_hdrs_with_direct_swift_infos",
    tags = FIXTURE_TAGS,
    deps = [
        ":child",
        ":swift_custom_module_name",
    ],
)

swift_test(
    name = "test_with_srcs",
    srcs = ["test.swift"],
    features = ["swift.label_as_module_name"],
    deps = [
        ":child",
    ],
)
