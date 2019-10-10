workspace(
    name = "build_bazel_rules_swift",
    managed_directories = {"@exampledeps": [".build"]},
)

load(
    "@build_bazel_rules_swift//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()

load(
    "@build_bazel_apple_support//lib:repositories.bzl",
    "apple_support_dependencies",
)

apple_support_dependencies()

load(
    "@com_google_protobuf//:protobuf_deps.bzl",
    "protobuf_deps",
)

protobuf_deps()

# I don't know where to put this since sub workspaces does not work well in bazel
# https://github.com/bazelbuild/bazel/issues/2391
load(
    "@build_bazel_rules_swift//swift:package.bzl",
    "swift_package_install",
)

swift_package_install(
    name = "exampledeps",
    package = "@//:Package.swift",
    package_resolved = "@//:Package.resolved",
    symlink_build_path = True,
    debug = True
)
