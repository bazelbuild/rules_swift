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

register_toolchains("@rules_swift//swift/toolchains:all")
\`\`\`
EOF
