#!/usr/bin/env bash
# Run SwiftPM tests and fail if the invocation only builds without discovering tests.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: scripts/swift-test-gate.sh PACKAGE_PATH [swift test args...]" >&2
    exit 2
fi

PACKAGE_PATH="$1"
shift

OUTPUT="$(mktemp)"
cleanup() {
    rm -f "$OUTPUT"
}
trap cleanup EXIT

set +e
swift test --package-path "$PACKAGE_PATH" "$@" 2>&1 | tee "$OUTPUT"
STATUS=${PIPESTATUS[0]}
set -e

if [[ "$STATUS" -ne 0 ]]; then
    exit "$STATUS"
fi

if ! grep -Eq 'Executed [1-9][0-9]* tests|Test run with [1-9][0-9]* tests|Test ".+" passed after' "$OUTPUT"; then
    echo "Error: swift test discovered zero tests for $PACKAGE_PATH" >&2
    exit 1
fi

exit 0
