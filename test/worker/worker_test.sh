#!/usr/bin/env bash

set -euo pipefail

readonly worker="$PWD/$1"
readonly compiler="$PWD/$2"
readonly test_name="$3"
cd "$TEST_TMPDIR"

readonly output_dir="bazel-out/config/bin"
export INCREMENTAL_DIR="$output_dir/_swift_incremental"
readonly dependencies=(module.swiftdeps module.priors source.swiftdeps)

mkdir -p "$output_dir"
cat >"$output_dir/module.json" <<EOF
{"source.swift": {"object": "$output_dir/source.o"}}
EOF

source_digest="source-v1"
dependency_digest="dependency-v1"
extra_arguments=""
universal_argument="-DOLD_DEFINE"
echo old >compiler_output

run_worker() {
	local expected_exit_code="${1:-0}"
	rm -rf observed_dependencies
	# Bazel removes declared outputs before executing an action.
	rm -f "$output_dir"/module.{swiftmodule,swiftdoc,swiftsourceinfo,h} \
		"$output_dir/source.o"
	cat >request.json <<EOF
{
  "arguments": [
    "-output-file-map", "$output_dir/module.json",
    "-emit-module-path", "$output_dir/module.swiftmodule",
    "-emit-objc-header-path", "$output_dir/module.h"
    $extra_arguments
  ],
  "inputs": [
    {"path": "source.swift", "digest": "$source_digest"},
    {"path": "Dependency.swiftmodule", "digest": "$dependency_digest"}
  ]
}
EOF
	# Requests are newline-delimited JSON. The worker exits with 254 at EOF;
	# the compilation's exit code is in its response.
	local worker_exit_code=0
	{
		tr -d '\n' <request.json
		printf '\n'
	} | "$worker" --persistent_worker "$compiler" "$universal_argument" \
		>response.json 2>worker.log || worker_exit_code=$?
	if [[ "$worker_exit_code" != 254 ]] ||
		! grep -Fq "\"exitCode\":$expected_exit_code," response.json; then
		cat response.json worker.log >&2
		echo "Expected compilation exit code $expected_exit_code" >&2
		exit 1
	fi
}

assert_dependencies_kept() {
	for dependency in "${dependencies[@]}"; do
		if [[ ! -f "observed_dependencies/$dependency" ]]; then
			echo "Expected the compiler to reuse $dependency" >&2
			exit 1
		fi
	done
}

assert_dependencies_removed() {
	for dependency in "${dependencies[@]}"; do
		if [[ -f "observed_dependencies/$dependency" ]]; then
			echo "Expected the worker to invalidate $dependency" >&2
			exit 1
		fi
	done
}

assert_module_outputs() {
	local expected="$1"
	for extension in swiftmodule swiftdoc swiftsourceinfo h; do
		if [[ "$(cat "$output_dir/module.$extension")" != "$expected" ]]; then
			echo "Expected module.$extension to contain '$expected'" >&2
			exit 1
		fi
	done
}

# Every test starts with a successful build and existing incremental state.
run_worker

case "$test_name" in
module_outputs_survive_failure)
	source_digest="source-v2"
	echo new >compiler_output
	touch fail_compilation
	run_worker 1

	# Recover without rewriting the module. The failed build's newer module
	# must survive even when Bazel has removed the declared outputs.
	rm fail_compilation
	touch skip_compilation
	run_worker
	assert_dependencies_kept
	assert_module_outputs new
	;;
source_changes_keep_dependencies)
	source_digest="source-v2"
	run_worker
	assert_dependencies_kept

	touch fail_compilation
	run_worker 1
	assert_dependencies_kept
	rm fail_compilation
	run_worker
	assert_dependencies_kept
	;;
changed_dependency_digest)
	# A cache hit can change a module's contents without a newer timestamp.
	# Changing only its Bazel digest must invalidate the compiler's records.
	dependency_digest="dependency-v2"
	run_worker
	assert_dependencies_removed
	run_worker
	assert_dependencies_kept
	;;
changed_arguments)
	extra_arguments=', "-DNEW_DEFINE"'
	run_worker
	assert_dependencies_removed
	run_worker
	assert_dependencies_kept
	;;
changed_universal_arguments)
	universal_argument="-DNEW_DEFINE"
	run_worker
	assert_dependencies_removed
	run_worker
	assert_dependencies_kept
	;;
missing_digest)
	dependency_digest=""
	run_worker
	assert_dependencies_removed
	# Equal but empty digests must not make subsequent builds reusable.
	run_worker
	assert_dependencies_removed
	;;
missing_input_record)
	rm -f "$INCREMENTAL_DIR/module.inputs.json"
	run_worker
	assert_dependencies_removed
	;;
corrupt_input_record)
	echo invalid-json >"$INCREMENTAL_DIR/module.inputs.json"
	run_worker
	assert_dependencies_removed
	;;
failed_dependency_change)
	dependency_digest="dependency-v2"
	touch fail_compilation
	run_worker 1
	assert_dependencies_removed

	# Returning to the old inputs must not reuse the failed build's state.
	dependency_digest="dependency-v1"
	rm fail_compilation
	run_worker
	assert_dependencies_removed
	;;
*)
	echo "Unknown test: $test_name" >&2
	exit 1
	;;
esac
