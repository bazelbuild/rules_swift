load("@rules_shell//shell:sh_test.bzl", "sh_test")
load("//test:transitions.bzl", "transition_binary")

# A module from `swift_import(is_framework = True)` must give its importers a
# `-framework` autolink entry. Only the final link reports a missing entry, so
# these tests check the archive instead of a linked binary.

transition_binary(
    name = "framework_client_explicit_module_map",
    testonly = True,
    target = "//test/fixtures/module_interface:framework_client",
    target_compatible_with = ["@platforms//os:macos"],
    transitive_features = ["swift.use_explicit_swift_module_map"],
)

sh_test(
    name = "explicit_module_framework_autolink_test",
    srcs = ["check_framework_autolink.sh"],
    args = [
        "ToyModule",
        "$(rootpaths :framework_client_explicit_module_map)",
    ],
    data = [":framework_client_explicit_module_map"],
    target_compatible_with = ["@platforms//os:macos"],
)
