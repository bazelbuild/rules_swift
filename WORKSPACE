workspace(name = "build_bazel_rules_swift")

load(
    "@build_bazel_rules_swift//swift:repositories.bzl",
    "swift_rules_dependencies",
)

swift_rules_dependencies()

load(
    "@build_bazel_rules_swift//swift:extras.bzl",
    "swift_rules_extra_dependencies",
)

swift_rules_extra_dependencies()

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

# For API doc generation
# This is a dev dependency, users should not need to install it
# so we declare it in the WORKSPACE
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "io_bazel_stardoc",
    sha256 = "3fd8fec4ddec3c670bd810904e2e33170bedfe12f90adf943508184be458c8bb",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/stardoc/releases/download/0.5.3/stardoc-0.5.3.tar.gz",
        "https://github.com/bazelbuild/stardoc/releases/download/0.5.3/stardoc-0.5.3.tar.gz",
    ],
)

http_archive(
    name = "transitive_swift_protobuf_repro",
    sha256 = "",
    urls = [
        "https://github.com/maxwellE/transitive_swift_protobuf_repro/archive/b436657547be46edaaf79816fb7e7b3f9f685e5d.zip",
    ],
    strip_prefix = "transitive_swift_protobuf_repro-b436657547be46edaaf79816fb7e7b3f9f685e5d"
)
