#!/usr/bin/env bash
# Smoke test the heist-plan Swift authoring compiler outside SwiftPM's test runner.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HEIST_PLAN_TOOL="${HEIST_PLAN_TOOL:-$REPO_ROOT/ButtonHeist/.build/debug/heist-plan}"
if [[ ! -x "$HEIST_PLAN_TOOL" ]]; then
    echo "Error: heist-plan executable not found at $HEIST_PLAN_TOOL" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heist-plan-compile.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SOURCE="$TMP_DIR/Plan.swift"
OUTPUT="$TMP_DIR/compiled.heist"
RENDERED="$TMP_DIR/rendered.swift"
EXPECTED="$TMP_DIR/expected.swift"

cat > "$SOURCE" <<'SWIFT'
import ThePlans

func makeHeist() throws -> HeistPlan {
    try HeistPlan("compiled") {
        Warn("from Swift")
    }
}
SWIFT

cat > "$EXPECTED" <<'SWIFT'
try HeistPlan("compiled") {
    Warn("from Swift")
}
SWIFT

"$HEIST_PLAN_TOOL" compile "$SOURCE" --entry makeHeist --output "$OUTPUT"
[[ -d "$OUTPUT" ]] || {
    echo "Error: compile did not produce a .heist package directory" >&2
    exit 1
}
[[ -f "$OUTPUT/manifest.json" ]] || {
    echo "Error: compile output is missing manifest.json" >&2
    exit 1
}
[[ -f "$OUTPUT/plan.json" ]] || {
    echo "Error: compile output is missing plan.json" >&2
    exit 1
}

"$HEIST_PLAN_TOOL" validate "$OUTPUT"
"$HEIST_PLAN_TOOL" render-swift "$OUTPUT" > "$RENDERED"
diff -u "$EXPECTED" "$RENDERED"
