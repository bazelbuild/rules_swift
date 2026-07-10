#!/usr/bin/env bash

set -euo pipefail

./tools/update_swift_release_files.py

if git diff --quiet; then
  echo "No Swift release updates found."
  exit 0
fi

timestamp="$(date -u +%Y%m%d%H%M%S)"
branch="automation/update-swift-releases-${timestamp}"
base_branch="${GITHUB_REF_NAME:-$(git branch --show-current)}"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git checkout -b "$branch"
git add swift/internal/extensions/swift_release_metadata.json
git commit -m "Update Swift release metadata"
git push origin "$branch"

gh pr create \
  --repo "$GITHUB_REPOSITORY" \
  --base "$base_branch" \
  --head "$branch" \
  --fill
