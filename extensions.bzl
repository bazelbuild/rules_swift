
load(
    "//swift/internal:swift_autoconfiguration.bzl",
    "swift_autoconfiguration",
)
def _impl(mctx):
    swift_autoconfiguration(name = "build_bazel_rules_swift_local_config")
foo = module_extension(

implementation = _impl)
