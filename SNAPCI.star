features(
  trigger_controller = "snapci", # make sure you have on_cool() defined if you turn on this flag
)

MAC_EXEC_REQUIREMENTS = {
    "os": "macos",
    "arch": "arm64",
    "vm_image": "snap-macos",
    "xcode_version": "16.0_16A242d"
}

on_pr(
    execs = [
        exec("run_cool", params = {
            "IS_COOL": False,
        }),
    ],
)

on_cool(
    execs = [
        exec("run_cool"),
    ],
)

on_comment(
    name = "on_comment_deploy",
    body = match.command("/deploy"),
    description = "Manually run a deploy command to dev GCS bucket",
    execs = [
        exec("run_deploy"),
    ],
)

on_comment(
    name = "on_comment_notcool",
    body = match.command("/notcool"),
    description = "Manually run cool script to upload ruleset archive to prod GCS bucket",
    execs = [
        exec("run_cool"),
    ],
)

run(
    name = "run_cool",
    description = "Runs the cool process",
    steps = [
        process("snapci/cool.sh"),
    ],
    params = {
        "IS_COOL": param.bool(default = True),
    },
    exec_requirements = MAC_EXEC_REQUIREMENTS,
)

run(
    name = "run_deploy",
    description = "Runs the deploy dev process",
    steps = [
        process("snapci/deploy.sh"),
    ],
    exec_requirements = MAC_EXEC_REQUIREMENTS,
)

