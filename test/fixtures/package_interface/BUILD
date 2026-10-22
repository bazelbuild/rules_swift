load("//swift:swift_library.bzl", "swift_library")
load("//test/fixtures:common.bzl", "FIXTURE_TAGS")

package(
    default_testonly = True,
    default_visibility = ["//test:__subpackages__"],
)

licenses(["notice"])

swift_library(
    name = "package_swiftinterface_library",
    package_name = "ExamplePackage",
    srcs = ["Library.swift"],
    library_evolution = True,
    module_name = "PackageLibrary",
    tags = FIXTURE_TAGS,
)

# Force textual interface loading even though the dependency also emits a
# binary module. The consumer deliberately does not enable library evolution:
# loading package interfaces must not depend on emitting one itself.
swift_library(
    name = "package_swiftinterface_consumer",
    package_name = "ExamplePackage",
    srcs = ["Consumer.swift"],
    copts = [
        "-Xfrontend",
        "-module-load-mode",
        "-Xfrontend",
        "only-interface",
    ],
    features = [
        "-swift.use_c_modules",
        "-swift.use_explicit_swift_module_map",
    ],
    tags = FIXTURE_TAGS,
    deps = [":package_swiftinterface_library"],
)
