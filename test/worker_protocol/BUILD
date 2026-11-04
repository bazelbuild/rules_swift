load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//test:transitions.bzl", "transition_binary")

transition_binary(
    name = "proto_library",
    testonly = True,
    target = "//test/fixtures/basic:first",
    worker_protocol = "proto",
)

build_test(
    name = "proto_worker_build_test",
    targets = [":proto_library"],
)
