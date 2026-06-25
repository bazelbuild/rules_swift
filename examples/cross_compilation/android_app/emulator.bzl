"""A dev module extension that downloads a hermetic Android emulator and a
system image, so `bazel run //examples/cross_compilation/android_app:run` can
boot an emulator and launch the example with nothing preinstalled.

macOS/arm64 only, to keep this illustrative delta small (it's the platform the
example's CI runs on). adb comes from `@androidsdk`; only the emulator and the
system image — which `@androidsdk` does not provide — are downloaded here.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

_EMULATOR_BUILD = """\
package(default_visibility = ["//visibility:public"])

exports_files(["emulator/emulator"])

filegroup(name = "all", srcs = glob(["emulator/**"]))
"""

_SYSTEM_IMAGE_BUILD = """\
package(default_visibility = ["//visibility:public"])

exports_files(["system.img"])

filegroup(name = "all", srcs = glob(["**"]))
"""

def _emulator_impl(_module_ctx):
    http_archive(
        name = "android_emulator",
        build_file_content = _EMULATOR_BUILD,
        sha256 = "25378c67fd5bd03178e3a478b866496da8545e969df3a7a26ce9167772ffc026",
        url = "https://dl.google.com/android/repository/emulator-darwin_aarch64-15565763.zip",
    )

    # A regular GPU-enabled AOSP (default) image, not the headless ATD image.
    http_archive(
        name = "android_system_image",
        build_file_content = _SYSTEM_IMAGE_BUILD,
        sha256 = "1447958a4c6747c44390ac5f5f4c894be6d1dfce93868a0385a95c5f0ae4c339",
        strip_prefix = "arm64-v8a",
        url = "https://dl.google.com/android/repository/sys-img/android/arm64-v8a-34_r04.zip",
    )

emulator = module_extension(implementation = _emulator_impl)
