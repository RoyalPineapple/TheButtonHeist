#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
FIXTURE_REPO="$FIXTURE_ROOT/repo"
LINT_OUTPUT=""
LINT_STATUS=0

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_lint() {
    set +e
    LINT_OUTPUT="$(
        BUTTONHEIST_SOURCE_ROOT="$FIXTURE_REPO" \
            "$REPO_ROOT/scripts/check-source-shape.sh" 2>&1
    )"
    LINT_STATUS=$?
    set -e
}

mkdir -p "$FIXTURE_REPO"
git -C "$REPO_ROOT" archive HEAD | tar -x -C "$FIXTURE_REPO"

cat > "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support/SourceShapeFixtures.swift" <<'EOF'
var onActorIsolated: (@MainActor (Int) -> Void)?
var onSendable: (@Sendable (Int) -> Void)?
EOF

run_lint
[[ "$LINT_STATUS" -eq 0 ]] || fail "source-shape lint rejected valid fixtures: $LINT_OUTPUT"

cat > "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support/SourceShapeFixtures.swift" <<'EOF'
typealias AlternateAccessibilityTarget = AccessibilityTarget

var onUnannotated: ((Int) -> Void)?
EOF

run_lint
[[ "$LINT_STATUS" -ne 0 ]] || fail "source-shape lint accepted invalid fixtures"
[[ "$LINT_OUTPUT" == *"alternate AccessibilityTarget typealias"* ]] \
    || fail "source-shape lint missed the alternate target alias: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"callback without isolation annotation"* ]] \
    || fail "source-shape lint missed the unannotated callback: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"onUnannotated"* ]] \
    || fail "callback diagnostic did not identify onUnannotated: $LINT_OUTPUT"

echo "PASS: SwiftSyntax source-shape guardrails"
