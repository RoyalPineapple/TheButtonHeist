#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$FIXTURE_ROOT/scripts" "$FIXTURE_ROOT/ButtonHeist/Sources/Fixture"
cp "$SCRIPT_DIR/check-source-shape.sh" "$FIXTURE_ROOT/scripts/check-source-shape.sh"

cat > "$FIXTURE_ROOT/ButtonHeist/Sources/Fixture/Violations.swift" <<'SWIFT'
private final class UnsafeBox: @unchecked Sendable {}
// @unchecked Sendable
private let ignoredString = "@unchecked Sendable"
SWIFT

# Bumper's repository-level architecture rules are covered by the real-repository
# invocation. This fixture isolates the platform-boundary guard.
BUMPER=true "$FIXTURE_ROOT/scripts/check-source-shape.sh" >"$FIXTURE_ROOT/output" 2>&1 || true

if ! grep -F "Violations.swift:1: UIKit/ObjC @unchecked Sendable outside TheInsideJob platform boundary" \
    "$FIXTURE_ROOT/output" >/dev/null; then
    echo "expected source-shape violations" >&2
    exit 1
fi

if grep -F "Violations.swift:2:" "$FIXTURE_ROOT/output" >/dev/null \
    || grep -F "Violations.swift:3:" "$FIXTURE_ROOT/output" >/dev/null; then
    echo "comments or strings produced a source-shape violation" >&2
    exit 1
fi
