#!/bin/bash

set -euo pipefail

readonly new_version=$1

cat > MODULE.bazel.new <<EOF
# Generated by update-module-version.sh. DO NOT EDIT.
module(
    name = "rules_swift",
    version = "$new_version",
    bazel_compatibility = [">=6.0.0"],
    compatibility_level = 1,
    repo_name = "build_bazel_rules_swift",
)

EOF

grep "# --- " -A1000 MODULE.bazel >> MODULE.bazel.new
mv MODULE.bazel.new MODULE.bazel
