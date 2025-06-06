#!/usr/bin/env bash

set -xeuo pipefail

source $(dirname $BASH_SOURCE)/utils.sh

# Xcode version is defined inside the EXEC_REQUIREMENTS
# of SNAPCI.star
echo "Building and testing rules_swift..."

# From bazelbuild/rules_swift/.bazelci/presubmit.yml
echo "Building and testing rules_swift..."
bzl build //... --disk_cache="" --remote_cache=""

if [[ "${IS_COOL:-false}" == "true" ]]; then
    deploy ""
else
    deploy "-dev"
fi
