#!/usr/bin/env bash

set -euo pipefail

# Record what the worker left for the compiler before producing new outputs.
mkdir -p observed_dependencies
for dependency in "$INCREMENTAL_DIR"/*.swiftdeps "$INCREMENTAL_DIR"/*.priors; do
	if [[ -f "$dependency" ]]; then
		cp "$dependency" observed_dependencies/
	fi
done

# A successful incremental compile may leave the previous outputs untouched.
if [[ -f skip_compilation ]]; then
	exit 0
fi

# The worker passes one quoted argument per line in a response file. These
# fixtures have no spaces or escaped characters in their arguments.
previous=""
while IFS= read -r argument; do
	argument="${argument#\"}"
	argument="${argument%\"}"
	case "$previous" in
	-emit-module-path)
		cp compiler_output "$argument"
		cp compiler_output "${argument%.swiftmodule}.swiftdoc"
		cp compiler_output "${argument%.swiftmodule}.swiftsourceinfo"
		;;
	-emit-objc-header-path)
		cp compiler_output "$argument"
		;;
	esac
	previous="$argument"
done <"${1#@}"

cp compiler_output "$INCREMENTAL_DIR/source.o"
touch "$INCREMENTAL_DIR/source.swiftdeps"
touch "$INCREMENTAL_DIR/module.swiftdeps"
touch "$INCREMENTAL_DIR/module.priors"

# Swift can update module outputs and dependency records before a job fails.
if [[ -f fail_compilation ]]; then
	exit 1
fi
