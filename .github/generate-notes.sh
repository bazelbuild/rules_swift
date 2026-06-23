#!/bin/bash

set -euo pipefail

readonly new_version=$1

cat <<EOF
## What's Changed

TODO

This release is compatible with: TODO

## MODULE.bazel Snippet

\`\`\`bzl
bazel_dep(name = "rules_swift", version = "$new_version")

swift = use_extension(
    "@rules_swift//swift:extensions.bzl",
    "swift",
)
swift.toolchain(
    name = "swift_toolchain",
    # Use "ubuntu22.04" or another supported platform on Linux.
    platforms = ["xcode"],
    swift_version = "6.3",
)
use_repo(swift, "swift_toolchain")

register_toolchains("@swift_toolchain//:all")
\`\`\`
EOF
