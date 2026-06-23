#!/usr/bin/env bash
# Compile an external SwiftPM consumer that imports ButtonHeist only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-external-import-contract"

fail() {
    echo "Error: $*" >&2
    exit 1
}

[[ -f "$FIXTURE_DIR/Package.swift" ]] || fail "missing external import fixture Package.swift"

IMPORTS="$(grep -R -nE '^[[:space:]]*import[[:space:]]+' "$FIXTURE_DIR/Sources" || true)"
[[ -n "$IMPORTS" ]] || fail "external import fixture must import ButtonHeist"
if printf '%s\n' "$IMPORTS" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+ButtonHeist([[:space:]]|$)'
then
    fail "external import fixture must import ButtonHeist only"
fi

if grep -nE 'product:[[:space:]]*"ThePlans"|name:[[:space:]]*"ThePlans"' "$FIXTURE_DIR/Package.swift"; then
    fail "external import fixture must depend on the ButtonHeist product only, not ThePlans"
fi

SCRATCH_PATH="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-import-contract-build.XXXXXX")"
SWIFT_CACHE_PATH="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-import-contract-cache.XXXXXX")"
cleanup() {
    rm -rf "$SCRATCH_PATH"
    rm -rf "$SWIFT_CACHE_PATH"
    rm -f "$FIXTURE_DIR/Package.resolved"
}
trap cleanup EXIT

echo "Compiling external ButtonHeist import contract fixture"
CLANG_MODULE_CACHE_PATH="$SWIFT_CACHE_PATH/clang" \
    swift build \
    --disable-sandbox \
    --cache-path "$SWIFT_CACHE_PATH/swiftpm" \
    --package-path "$FIXTURE_DIR" \
    --scratch-path "$SCRATCH_PATH"
