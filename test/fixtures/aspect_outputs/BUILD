load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":rules.bzl", "collect_outputs")

package(default_visibility = ["//test:__subpackages__"])

swift_interop_hint(
    name = "hint",
    module_name = "AspectModule",
    tags = FIXTURE_TAGS,
)

cc_library(
    name = "module",
    hdrs = ["module.h"],
    aspect_hints = [":hint"],
    features = [
        "swift.emit_c_module",
        "swift.use_c_modules",
    ],
    tags = FIXTURE_TAGS,
)

collect_outputs(
    name = "outputs",
    custom_one = ":module",
    custom_two = ":module",
    default = ":module",
    tags = FIXTURE_TAGS,
)
