#!/usr/bin/env bash

set -euo pipefail

# Observe the worker's invalidation decisions before Swift updates its records.
mkdir -p observed_dependencies
for dependency in "$INCREMENTAL_DIR"/*.swiftdeps "$INCREMENTAL_DIR"/*.priors; do
	if [[ -f "$dependency" ]]; then
		cp "$dependency" observed_dependencies/
	fi
done

# Forward Swift's response file unchanged, including its argument quoting.
if [[ "$OSTYPE" == darwin* ]]; then
	exec /usr/bin/xcrun "$WORKER_TEST_COMPILER" "$@"
fi
exec "$WORKER_TEST_COMPILER" "$@"
