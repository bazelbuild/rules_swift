load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library_group")
package(default_visibility = ["//visibility:public"])

config_setting(
    name = "xcode_16_3_0_16E140",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "16.3.0.16E140",
    },
)

swift_library_group(
    name = "system_sdks",
    deps = select({
        ":xcode_16_3_0_16E140": ["//system_sdks/16.3.0.16E140:system_sdks"],
        "//conditions:default": [],
    }),
)

swift_library_group(
    name = "testonly_system_sdks",
    testonly = True,
    deps = select({
        ":xcode_16_3_0_16E140": ["//system_sdks/16.3.0.16E140:testonly_system_sdks"],
        "//conditions:default": [],
    }),
)
