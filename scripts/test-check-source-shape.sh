#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$FIXTURE_ROOT/scripts" "$FIXTURE_ROOT/ButtonHeist/Sources/Fixture"
cp "$SCRIPT_DIR/check-source-shape.sh" "$FIXTURE_ROOT/scripts/check-source-shape.sh"

cat > "$FIXTURE_ROOT/ButtonHeist/Sources/Fixture/Violations.swift" <<'SWIFT'
public struct Fixture {}

public func tupleResult() -> (Int, String) { (1, "one") }

package let tupleProperty: (Int, String) = (1, "one")

public typealias LegacyFixture = Fixture

@available(*, deprecated)
public func oldFixture() {}

private let erased: Any = 1
private final class UnsafeBox: @unchecked Sendable {}
nonisolated(unsafe) private var unsafeValue = 0

// swiftlint:disable:next force_cast
private let castValue = erased as! Int

private let ignoredString = "Any @unchecked Sendable nonisolated(unsafe) swiftlint:disable"
// Any @unchecked Sendable nonisolated(unsafe) swiftlint:disable
SWIFT

if "$FIXTURE_ROOT/scripts/check-source-shape.sh" >"$FIXTURE_ROOT/output" 2>&1; then
    echo "expected source-shape violations" >&2
    exit 1
fi

expected_diagnostics=(
    "Violations.swift:3: exported tuple return type"
    "Violations.swift:5: exported tuple property type"
    "Violations.swift:7: exported top-level typealias outside canonical ButtonHeistDSL facade"
    "Violations.swift:10: exported compatibility/legacy helper"
    "Violations.swift:12: unallowlisted Any type"
    "Violations.swift:13: UIKit/ObjC @unchecked Sendable outside TheInsideJob platform boundary"
    "Violations.swift:13: unallowlisted @unchecked Sendable"
    "Violations.swift:14: unallowlisted nonisolated(unsafe)"
    "Violations.swift:16: unallowlisted swiftlint:disable"
)

for diagnostic in "${expected_diagnostics[@]}"; do
    grep -F "$diagnostic" "$FIXTURE_ROOT/output" >/dev/null
done

if grep -F "Violations.swift:19:" "$FIXTURE_ROOT/output" >/dev/null \
    || grep -F "Violations.swift:20:" "$FIXTURE_ROOT/output" >/dev/null; then
    echo "comments or strings produced a source-shape violation" >&2
    exit 1
fi
