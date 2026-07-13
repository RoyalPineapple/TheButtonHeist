#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCTION_GATE="$SCRIPT_DIR/../check-swift-api-breaking-changes.sh"
FIXTURE_ROOT="$(mktemp -d)"
FIXTURE_REPO="$FIXTURE_ROOT/repo"
GATE_OUTPUT=""
GATE_STATUS=0

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_status() {
    local expected="$1"
    [[ "$GATE_STATUS" -eq "$expected" ]] \
        || fail "expected status $expected, got $GATE_STATUS: $GATE_OUTPUT"
}

assert_output_contains() {
    local expected="$1"
    [[ "$GATE_OUTPUT" == *"$expected"* ]] \
        || fail "missing output '$expected': $GATE_OUTPUT"
}

write_gate() {
    local exemption="$1"
    local gate="$FIXTURE_REPO/scripts/check-swift-api-breaking-changes.sh"
    local rewritten="$gate.rewritten"

    cp "$PRODUCTION_GATE" "$gate"
    [[ "$(grep -c 'Add only diagnostics absent' "$gate")" -eq 1 ]] \
        || fail "production gate exemption placeholder changed"
    awk -v exemption="$exemption" '
        /Add only diagnostics absent/ { print "    \"" exemption "\""; next }
        { print }
    ' "$gate" > "$rewritten"
    mv "$rewritten" "$gate"
    chmod +x "$gate"
}

run_gate() {
    local diagnostics="$1"

    rm -f "$FIXTURE_ROOT/swift-arguments"
    set +e
    GATE_OUTPUT="$(
        cd "$FIXTURE_REPO" && \
            PATH="$FIXTURE_ROOT/bin:$PATH" \
            SWIFT_ARGUMENTS_FILE="$FIXTURE_ROOT/swift-arguments" \
            SWIFT_DIAGNOSTICS="$diagnostics" \
            BUTTONHEIST_SWIFT_API_BASELINE_TAG="fixture-baseline" \
            scripts/check-swift-api-breaking-changes.sh 2>&1
    )"
    GATE_STATUS=$?
    set -e
}

mkdir -p "$FIXTURE_REPO/scripts" "$FIXTURE_ROOT/bin"

cat > "$FIXTURE_REPO/Package.swift" <<'EOF'
let package = Package(
    products: [
        .library(name: "ThePlans", targets: ["ThePlans"]),
        .library(name: "TheScore", targets: ["TheScore"]),
        .library(name: "ButtonHeistDSL", targets: ["ButtonHeistDSL"]),
        .library(name: "TheInsideJob", targets: ["TheInsideJob"]),
        .library(name: "ButtonHeistTesting", targets: ["ButtonHeistTesting"]),
        .library(name: "ButtonHeist", targets: ["ButtonHeist"]),
    ]
)
EOF

cat > "$FIXTURE_ROOT/bin/swift" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$SWIFT_ARGUMENTS_FILE"
printf '%s\n' "$SWIFT_DIAGNOSTICS"
exit 1
EOF
chmod +x "$FIXTURE_ROOT/bin/swift"

write_gate "baseline-owned diagnostic"
git -C "$FIXTURE_REPO" init --quiet
git -C "$FIXTURE_REPO" config user.email "fixture@example.com"
git -C "$FIXTURE_REPO" config user.name "Fixture"
git -C "$FIXTURE_REPO" add Package.swift scripts/check-swift-api-breaking-changes.sh
git -C "$FIXTURE_REPO" commit --quiet -m "fixture baseline"
git -C "$FIXTURE_REPO" tag fixture-baseline

run_gate "API breakage: baseline-owned diagnostic"
assert_status 2
assert_output_contains "stale Swift API breakage exemption inherited from fixture-baseline"
[[ ! -e "$FIXTURE_ROOT/swift-arguments" ]] \
    || fail "stale exemption reached the Swift API checker"

write_gate "deliberate current-only diagnostic mentioning API breakage: literally"
run_gate "error: API breakage: deliberate current-only diagnostic mentioning API breakage: literally"
assert_status 0
assert_output_contains "Only intentional Swift API breakage detected:"

cat > "$FIXTURE_ROOT/expected-swift-arguments" <<'EOF'
package
diagnose-api-breaking-changes
fixture-baseline
--products
ThePlans
TheScore
ButtonHeistDSL
TheInsideJob
ButtonHeistTesting
ButtonHeist
EOF
diff -u "$FIXTURE_ROOT/expected-swift-arguments" "$FIXTURE_ROOT/swift-arguments" \
    || fail "the gate did not discover all six public products"

run_gate "API breakage: deliberate current-only diagnostic mentioning API breakage: literally with suffix"
assert_status 1
assert_output_contains "deliberate current-only diagnostic mentioning API breakage: literally with suffix"

run_gate $'API breakage: deliberate current-only diagnostic mentioning API breakage: literally\nAPI breakage: unrelated diagnostic'
assert_status 1
assert_output_contains $'Unexpected Swift API breakage detected:\n  - unrelated diagnostic'

echo "PASS: Swift API breakage exemption gate"
