"""Tests for custom Swift driver executables on Swift toolchains."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//swift:providers.bzl", "SwiftToolchainInfo")

_FAKE_DRIVER = "test/fixtures/toolchains/fake_swift_driver.sh"

def _custom_driver_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    tool_config = target_under_test[SwiftToolchainInfo].tool_configs.get(
        "SwiftCompile",
    )
    if not tool_config:
        unittest.fail(env, "Expected a 'SwiftCompile' tool config.")
        return analysistest.end(env)

    executable = tool_config.executable
    asserts.equals(env, "File", type(executable), "executable type")
    if type(executable) == "File":
        asserts.equals(
            env,
            _FAKE_DRIVER,
            executable.short_path,
            "executable short_path",
        )

    asserts.equals(
        env,
        ["--driver-mode=swiftc"],
        tool_config.args[:1],
        "driver mode argument",
    )

    return analysistest.end(env)

custom_driver_test = analysistest.make(_custom_driver_test_impl)

custom_driver_from_flag_test = analysistest.make(
    _custom_driver_test_impl,
    config_settings = {
        str(Label("//swift:default_swift_executable")): str(
            Label("//test/fixtures/toolchains:fake_swift_driver.sh"),
        ),
    },
)

def custom_swift_driver_test_suite(name, tags = []):
    """Test suite for custom Swift driver executables.

    Args:
        name: The base name to be used in targets created by this macro.
        tags: Additional tags to apply to each test.
    """
    all_tags = [name] + tags

    # Verify that swift_toolchain uses the driver set by swift_executable.
    custom_driver_test(
        name = "{}_swift_toolchain_attr".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/toolchains:toolchain_with_custom_driver",
    )

    # Verify that swift_toolchain uses the driver set by default_swift_executable.
    custom_driver_from_flag_test(
        name = "{}_swift_toolchain_flag".format(name),
        tags = all_tags,
        target_under_test = "//test/fixtures/toolchains:_toolchain_macos_arm64_with_sdkroot",
    )

    # Verify that xcode_swift_toolchain uses the driver set by default_swift_executable.
    custom_driver_from_flag_test(
        name = "{}_xcode_toolchain_flag".format(name),
        tags = all_tags,
        target_compatible_with = ["@platforms//os:macos"],
        target_under_test = "//test/fixtures/toolchains:resolved_swift_toolchain",
    )

    native.test_suite(
        name = name,
        tags = all_tags,
    )
