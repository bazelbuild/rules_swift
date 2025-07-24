load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library_group")
package(default_visibility = ["//visibility:public"])

config_setting(
    name = "macos_x86_64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "macos_arm64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:arm64",
    ],
)

config_setting(
    name = "ios_device_arm64",
    constraint_values = [
        "@platforms//os:ios",
        "@platforms//cpu:arm64",
        "@build_bazel_apple_support//constraints:device",
    ],
)

config_setting(
    name = "ios_sim_x86_64",
    constraint_values = [
        "@platforms//os:ios",
        "@platforms//cpu:x86_64",
        "@build_bazel_apple_support//constraints:simulator",
    ],
)

config_setting(
    name = "ios_sim_arm64",
    constraint_values = [
        "@platforms//os:ios",
        "@platforms//cpu:arm64",
        "@build_bazel_apple_support//constraints:simulator",
    ],
)

config_setting(
    name = "watchos_sim_arm64",
    constraint_values = [
        "@platforms//os:watchos",
        "@platforms//cpu:arm64",
        "@build_bazel_apple_support//constraints:simulator",
    ],
)

config_setting(
    name = "watchos_sim_x86_64",
    constraint_values = [
        "@platforms//os:watchos",
        "@platforms//cpu:x86_64",
        "@build_bazel_apple_support//constraints:simulator",
    ],
)

config_setting(
    name = "watchos_device_arm64_32",
    constraint_values = [
        "@platforms//os:watchos",
        "@platforms//cpu:arm64_32",
        "@build_bazel_apple_support//constraints:device",
    ],
)

swift_library_group(
    name = "system_sdks",
    deps = select({
        "ios_device_arm64": ["//system_sdks/16.3.0.16E140/iPhoneOS/arm64:all_generated_targets"],
        "watchos_device_arm64_32": ["//system_sdks/16.3.0.16E140/WatchOS/arm64_32:all_generated_targets"],
        "watchos_sim_arm64": ["//system_sdks/16.3.0.16E140/WatchSimulator/arm64:all_generated_targets"],
        "watchos_sim_x86_64": ["//system_sdks/16.3.0.16E140/WatchSimulator/x86_64:all_generated_targets"],
        "ios_sim_arm64": ["//system_sdks/16.3.0.16E140/iPhoneSimulator/arm64:all_generated_targets"],
        "ios_sim_x86_64": ["//system_sdks/16.3.0.16E140/iPhoneSimulator/x86_64:all_generated_targets"],
        "macos_arm64": ["//system_sdks/16.3.0.16E140/MacOSX/arm64:all_generated_targets"],
        "macos_x86_64": ["//system_sdks/16.3.0.16E140/MacOSX/x86_64:all_generated_targets"],
        "//conditions:default": [],
    }),
)


swift_library_group(
    name = "testonly_system_sdks",
    testonly = True,
    deps = select({
        "ios_device_arm64": ["//system_sdks/16.3.0.16E140/iPhoneOS/arm64:all_generated_testonly_targets"],
        "watchos_device_arm64_32": ["//system_sdks/16.3.0.16E140/WatchOS/arm64_32:all_generated_testonly_targets"],
        "watchos_sim_arm64": ["//system_sdks/16.3.0.16E140/WatchSimulator/arm64:all_generated_testonly_targets"],
        "watchos_sim_x86_64": ["//system_sdks/16.3.0.16E140/WatchSimulator/x86_64:all_generated_testonly_targets"],
        "ios_sim_arm64": ["//system_sdks/16.3.0.16E140/iPhoneSimulator/arm64:all_generated_testonly_targets"],
        "ios_sim_x86_64": ["//system_sdks/16.3.0.16E140/iPhoneSimulator/x86_64:all_generated_testonly_targets"],
        "macos_arm64": ["//system_sdks/16.3.0.16E140/MacOSX/arm64:all_generated_testonly_targets"],
        "macos_x86_64": ["//system_sdks/16.3.0.16E140/MacOSX/x86_64:all_generated_testonly_targets"],
        "//conditions:default": [],
    }),
)
