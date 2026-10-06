#!/usr/bin/env bash

set -euo pipefail

export WORKER_TEST_WORKER="$PWD/$1"
readonly observer="$PWD/$2"
readonly test_name="$3"
compiler="$4"
if [[ "$compiler" == */* && "$compiler" != /* ]]; then
	compiler="$PWD/$compiler"
fi
shift 4
readonly compiler
export WORKER_TEST_COMPILER="$compiler"
compiler_arguments=(--driver-mode=swiftc "$@")
cd "$TEST_TMPDIR"

readonly output_dir="bazel-out/config/bin"
export INCREMENTAL_DIR="$output_dir/_swift_incremental"

compile() {
	"$WORKER_TEST_WORKER" "$compiler" "${compiler_arguments[@]}" "$@"
}

# Worker digests are opaque strings. Compute them from the actual fixture bytes.
digest() {
	cksum <"$1" | awk '{print $1 ":" $2}'
}

build_dependency() {
	echo "public typealias Value = $1" >Dependency.swift
	compile -emit-module -module-name Dependency Dependency.swift \
		-emit-module-path Dependency.swiftmodule
	# Reproduce cache restoration: changed bytes with an old timestamp.
	touch -t 200001010000 Dependency.swiftmodule
}

write_source() {
	api="$1"
	cat >source.swift <<EOF_SOURCE
import Dependency

public func $api() -> Int {
#if NEW_DEFINE
    return 100 + MemoryLayout<Dependency.Value>.size
#else
    return MemoryLayout<Dependency.Value>.size
#endif
}
EOF_SOURCE
	# Use distinct timestamps without sleeps, even on coarse filesystems.
	touch -t "$2" source.swift
}

mkdir -p "$output_dir"
cat >"$output_dir/module.json" <<EOF_MAP
{"source.swift": {"object": "$output_dir/source.o"}}
EOF_MAP

extra_arguments=""
if [[ "$test_name" == module_outputs_survive_failure ]]; then
	# Match the default rules_swift configuration. An uncached source-info file
	# would force older workers to re-emit the module and hide the stale module.
	extra_arguments=', "-avoid-emit-module-source-info"'
fi
universal_argument="-DOLD_DEFINE"
missing_digest=false
fail_output_copy=false
hashing_argument=""
if [[ "${WORKER_TEST_FILE_HASHING:-0}" == 1 &&
	"$test_name" != changed_dependency_digest_without_hashing ]]; then
	hashing_argument=', "-Xwrapped-swift=-enable-incremental-file-hashing"'
fi
compile --version
echo "Incremental file hashing: ${hashing_argument:-disabled}"
build_dependency Int32
write_source oldAPI 202001010000

run_worker() {
	local expected_exit_code="${1:-0}"
	local dependency_digest
	dependency_digest="$(digest Dependency.swiftmodule)"
	if "$missing_digest"; then
		dependency_digest=""
	fi
	rm -rf observed_dependencies
	# Bazel removes declared outputs before executing an action.
	rm -f "$output_dir"/module.{swiftmodule,swiftdoc,swiftsourceinfo,h} \
		"$output_dir/source.o"
	if "$fail_output_copy"; then
		mkdir "$output_dir/source.o"
	fi
	cat >request.json <<EOF_REQUEST
{
  "arguments": [
    "-c", "-parse-as-library", "source.swift", "-I", ".",
    "-module-name", "WorkerModule", "-emit-module",
    "-module-cache-path", "$TEST_TMPDIR/module-cache",
    "-output-file-map", "$output_dir/module.json",
    "-emit-module-path", "$output_dir/module.swiftmodule",
    "-emit-objc-header-path", "$output_dir/module.h"
    $hashing_argument
    $extra_arguments
  ],
  "inputs": [
    {"path": "source.swift", "digest": "$(digest source.swift)"},
    {"path": "Dependency.swiftmodule", "digest": "$dependency_digest"},
    {"path": "$output_dir/module.json", "digest": "$(digest "$output_dir/module.json")"}
  ]
}
EOF_REQUEST
	# Requests are newline-delimited JSON. The worker exits with 254 at EOF;
	# the compilation's exit code is in its response.
	local worker_exit_code=0
	{
		tr -d '\n' <request.json
		printf '\n'
	} | "$WORKER_TEST_WORKER" --persistent_worker "$observer" \
		"${compiler_arguments[@]}" "$universal_argument" \
		>response.json 2>worker.log || worker_exit_code=$?
	if [[ "$worker_exit_code" != 254 ]] ||
		! grep -Fq "\"exitCode\":$expected_exit_code," response.json; then
		cat response.json worker.log >&2
		echo "Expected compilation exit code $expected_exit_code" >&2
		exit 1
	fi
	if "$fail_output_copy"; then
		rmdir "$output_dir/source.o"
		grep -Fq 'Could not copy' response.json
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
	local extensions=(swiftmodule swiftdoc h)
	if [[ "$test_name" != module_outputs_survive_failure ]]; then
		extensions+=(swiftsourceinfo)
	fi
	for extension in "${extensions[@]}"; do
		if [[ ! -s "$output_dir/module.$extension" ]]; then
			echo "Missing module.$extension" >&2
			exit 1
		fi
	done
	# A client must see the current module API and execute the current object.
	# Use the filename expected by Swift's module lookup.
	cp "$output_dir/module.swiftmodule" "$output_dir/WorkerModule.swiftmodule"
	cat >main.swift <<EOF_MAIN
import WorkerModule
print($api())
EOF_MAIN
	compile main.swift "$output_dir/source.o" -I "$output_dir" -I . -o client
	local actual
	actual="$(./client)"
	if [[ "$actual" != "$expected" ]]; then
		echo "Expected client to print $expected, got $actual" >&2
		exit 1
	fi
}

# Every test starts with real outputs and real incremental dependency records.
run_worker
assert_module_outputs 4
# Drivers differ in whether the module record is .swiftdeps or .priors.
dependencies=(source.swiftdeps)
for record in module.swiftdeps module.priors; do
	if [[ -f "$INCREMENTAL_DIR/$record" ]]; then
		dependencies+=("$record")
	fi
done
[[ "${#dependencies[@]}" -gt 1 ]]

case "$test_name" in
module_outputs_survive_failure)
	write_source newAPI 202001010001
	fail_output_copy=true
	run_worker 1
	assert_dependencies_kept
	# Swift succeeded and updated its records, but publishing the object failed.
	# The retry must preserve the newer module even if Swift skips compilation.
	cp "$INCREMENTAL_DIR/source.o" expected.o
	touch -r "$INCREMENTAL_DIR/module.swiftmodule" module_timestamp
	fail_output_copy=false
	run_worker
	assert_dependencies_kept
	cmp expected.o "$output_dir/source.o"
	assert_module_outputs 4
	if [[ "$INCREMENTAL_DIR/module.swiftmodule" -nt module_timestamp ||
		"$INCREMENTAL_DIR/module.swiftmodule" -ot module_timestamp ]]; then
		echo 'Expected Swift to reuse the module on the retry' >&2
		exit 1
	fi
	;;
changed_dependency_digest | changed_dependency_digest_without_hashing)
	build_dependency Int64
	run_worker
	assert_module_outputs 8
	assert_dependencies_removed
	run_worker
	assert_dependencies_kept
	assert_module_outputs 8
	;;
changed_arguments)
	extra_arguments=', "-DNEW_DEFINE"'
	run_worker
	assert_dependencies_removed
	assert_module_outputs 104
	run_worker
	assert_dependencies_kept
	;;
changed_universal_arguments)
	universal_argument="-DNEW_DEFINE"
	run_worker
	assert_dependencies_removed
	assert_module_outputs 104
	run_worker
	assert_dependencies_kept
	;;
missing_digest)
	missing_digest=true
	run_worker
	assert_dependencies_removed
	# Equal but empty digests must not make subsequent builds reusable.
	run_worker
	assert_dependencies_removed
	assert_module_outputs 4
	;;
missing_input_record)
	rm -f "$INCREMENTAL_DIR/module.inputs.json"
	run_worker
	assert_dependencies_removed
	assert_module_outputs 4
	;;
corrupt_input_record)
	echo invalid-json >"$INCREMENTAL_DIR/module.inputs.json"
	run_worker
	assert_dependencies_removed
	assert_module_outputs 4
	;;
failed_dependency_change)
	cp Dependency.swiftmodule original.swiftmodule
	build_dependency Int64
	fail_output_copy=true
	run_worker 1
	assert_dependencies_removed

	# Returning to the old inputs must not reuse the failed build's state.
	cp original.swiftmodule Dependency.swiftmodule
	touch -t 200001010000 Dependency.swiftmodule
	fail_output_copy=false
	run_worker
	assert_dependencies_removed
	assert_module_outputs 4
	;;
*)
	echo "Unknown test: $test_name" >&2
	exit 1
	;;
esac
