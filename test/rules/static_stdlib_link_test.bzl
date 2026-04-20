# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0

"""Transition rule that forwards a `swift_binary` built with `swift.static_stdlib`.

Used to wrap a `swift_binary` target so that it can be consumed as `data` by an
`sh_test` that inspects the linked ELF for dynamic Swift runtime references.
"""

def _enable_static_stdlib_impl(settings, _attr):
    existing = list(settings["//command_line_option:features"])
    if "swift.static_stdlib" not in existing:
        existing.append("swift.static_stdlib")
    return {"//command_line_option:features": existing}

_enable_static_stdlib_transition = transition(
    implementation = _enable_static_stdlib_impl,
    inputs = ["//command_line_option:features"],
    outputs = ["//command_line_option:features"],
)

def _with_static_stdlib_impl(ctx):
    target = ctx.attr.target[0]
    return [
        DefaultInfo(
            files = target[DefaultInfo].files,
            runfiles = target[DefaultInfo].default_runfiles,
        ),
    ]

with_static_stdlib = rule(
    attrs = {
        "target": attr.label(
            cfg = _enable_static_stdlib_transition,
            mandatory = True,
        ),
    },
    doc = """\
Rebuilds `target` with `--features=swift.static_stdlib` added and forwards its
files. Intended to be referenced via `data` on an `sh_test`.
""",
    implementation = _with_static_stdlib_impl,
)
