"""Simple rule to emulate apple_static_framework_import"""

load(
    "@bazel_tools//tools/cpp:toolchain_utils.bzl",
    "use_cpp_toolchain",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

_CPP_TOOLCHAIN_TYPE = Label("@bazel_tools//tools/cpp:toolchain_type")

def _impl(ctx):
    binary1 = ctx.actions.declare_file("framework1.framework/framework1")
    ctx.actions.write(binary1, "empty")

    binary2 = ctx.actions.declare_file("framework2.framework/framework2")
    ctx.actions.write(binary2, "empty")

    cc_toolchain = ctx.exec_groups["default"].toolchains[_CPP_TOOLCHAIN_TYPE].cc
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        language = "objc",
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )

    return CcInfo(
        linking_context = cc_common.create_linking_context(
            linker_inputs = depset([
                cc_common.create_linker_input(
                    owner = ctx.label,
                    libraries = depset([
                        cc_common.create_library_to_link(
                            actions = ctx.actions,
                            cc_toolchain = cc_toolchain,
                            feature_configuration = feature_configuration,
                            static_library = binary1,
                        ),
                        cc_common.create_library_to_link(
                            actions = ctx.actions,
                            cc_toolchain = cc_toolchain,
                            dynamic_library = binary2,
                            feature_configuration = feature_configuration,
                        ),
                    ]),
                ),
            ]),
        ),
    )

fake_framework = rule(
    implementation = _impl,
    attrs = {
        "_cc_toolchain": attr.label(
            default = Label("@bazel_tools//tools/cpp:current_cc_toolchain"),
            doc = "The C++ toolchain to use.",
        ),
    },
    exec_groups = {
        # An execution group that has no specific platform requirements. This
        # ensures that the execution platform of this Swift toolchain does not
        # unnecessarily constrain the execution platform of the C++ toolchain.
        "default": exec_group(
            toolchains = use_cpp_toolchain(),
        ),
    },
    fragments = ["cpp"],
)
