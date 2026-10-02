#!/usr/bin/env bash

set -euo pipefail

indexstore="$1"
units=$(find -L "$indexstore" -path '*/units/*' -type f -print)
if [[ -z "$units" ]]; then
  echo "No units were imported into $indexstore" >&2
  exit 1
fi

for source in first.swift second.swift; do
  records=$(find -L "$indexstore" -path '*/records/*' -name "*$source*" -type f -print)
  if [[ -z "$records" ]]; then
    echo "No index record was imported for $source" >&2
    exit 1
  fi
  while IFS= read -r record; do
    if [[ "$(head -c 5 "$record")" != CIDXR ]]; then
      echo "Index record is not compressed: $record" >&2
      exit 1
    fi
  done <<< "$records"
done
