package(default_visibility = ["//visibility:public"])

licenses(["notice"])

config_setting(
    name = "msvc",
    flag_values = {
        "@bazel_tools//tools/cpp:compiler": "msvc-cl",
    },
    visibility = [
        "//:__subpackages__",
    ],
)

config_setting(
    name = "clang-cl",
    flag_values = {
        "@bazel_tools//tools/cpp:compiler": "clang-cl",
    },
    visibility = [
        "//:__subpackages__",
    ],
)
