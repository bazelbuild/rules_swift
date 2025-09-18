load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library_group")
package(default_visibility = ["//visibility:public"])

# Xcode 16.3
config_setting(
    name = "xcode_16_3_0_16E140",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "16.3.0.16E140",
    },
)

# Xcode 26 Beta 4
config_setting(
    name = "xcode_26_0_0_17A324",
    flag_values = {
        "@bazel_tools//tools/osx:xcode_version_flag_exact": "26.0.0.17A324",
    },
)

swift_library_group(
    name = "system_sdks",
    deps = select({
        ":xcode_16_3_0_16E140": ["//system_sdks/16.3.0.16E140:system_sdks"],
        ":xcode_26_0_0_17A324": ["//system_sdks/26.0.0.17A324:system_sdks"],
        "//conditions:default": [],
    }),
)

swift_library_group(
    name = "testonly_system_sdks",
    testonly = True,
    deps = select({
        ":xcode_16_3_0_16E140": ["//system_sdks/16.3.0.16E140:testonly_system_sdks"],
        ":xcode_26_0_0_17A324": ["//system_sdks/26.0.0.17A324:testonly_system_sdks"],
        "//conditions:default": [],
    }),
)
