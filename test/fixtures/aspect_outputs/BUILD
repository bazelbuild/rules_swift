load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("//swift:swift_interop_hint.bzl", "swift_interop_hint")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")
load(":rules.bzl", "collect_aspect_outputs")

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

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

collect_aspect_outputs(
    name = "outputs",
    custom_a = ":module",
    custom_b = ":module",
    default = ":module",
    tags = FIXTURE_TAGS,
)
