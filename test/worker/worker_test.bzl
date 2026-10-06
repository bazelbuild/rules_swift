"""Runs worker regression tests with the configured Swift compiler."""

load("@bazel_skylib//lib:shell.bzl", "shell")

# buildifier: disable=bzl-visibility
load(
    "//swift/internal:action_names.bzl",
    "SWIFT_ACTION_AUTOLINK_EXTRACT",
    "SWIFT_ACTION_COMPILE",
)

# buildifier: disable=bzl-visibility
load("//swift/internal:feature_names.bzl", "SWIFT_FEATURE_INCREMENTAL_FILE_HASHING")

def _worker_test_impl(ctx):
    toolchain = ctx.toolchains["//toolchains:toolchain_type"].swift_toolchain
    compiler = toolchain.tool_configs[SWIFT_ACTION_COMPILE]
    files = [ctx.file._script, ctx.file._observer, ctx.executable._worker]
    files.extend(compiler.additional_tools)

    # The test also links a client, which invokes the autolink extractor on Linux.
    autolink_extractor = toolchain.tool_configs.get(SWIFT_ACTION_AUTOLINK_EXTRACT)
    if autolink_extractor:
        files.extend(autolink_extractor.additional_tools)
        if type(autolink_extractor.executable) == "File":
            files.append(autolink_extractor.executable)

    executable = compiler.executable
    if type(executable) == "File":
        files.append(executable)
        executable = executable.short_path
    elif executable.startswith("external/"):
        executable = "../" + executable.removeprefix("external/")

    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = runner,
        content = "#!/usr/bin/env bash\nexec bash {} \"$@\"\n".format(" ".join([
            shell.quote(arg)
            for arg in [
                ctx.file._script.short_path,
                ctx.executable._worker.short_path,
                ctx.file._observer.short_path,
                ctx.attr.scenario,
                executable,
            ] + compiler.args
        ])),
        is_executable = True,
    )
    return [
        DefaultInfo(
            executable = runner,
            runfiles = ctx.runfiles(files = files).merge(ctx.attr._worker[DefaultInfo].default_runfiles),
        ),
        testing.ExecutionInfo(compiler.execution_requirements),
        testing.TestEnvironment(compiler.env | {
            "WORKER_TEST_FILE_HASHING": "1" if SWIFT_FEATURE_INCREMENTAL_FILE_HASHING in toolchain.requested_features else "0",
        }),
    ]

worker_test = rule(
    implementation = _worker_test_impl,
    attrs = {
        "scenario": attr.string(mandatory = True),
        "_observer": attr.label(default = "observe_swiftc.sh", allow_single_file = True),
        "_script": attr.label(default = "worker_test.sh", allow_single_file = True),
        "_worker": attr.label(default = "//tools/worker:worker", executable = True, cfg = "exec"),
    },
    test = True,
    toolchains = ["//toolchains:toolchain_type"],
)
